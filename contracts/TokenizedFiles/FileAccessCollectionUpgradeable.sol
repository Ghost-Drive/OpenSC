// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@ghostdrive/signer/sol/contracts/SignatureAuth.sol";

import { az09Dash } from "../libs/az09Dash.sol";
import { ToString } from "../libs/ToString.sol";
import "../PaidActions.sol";
import "./interfaces/IFileActionCounter.sol";
import "./interfaces/IFileAccessCollectionUpgradeable.sol";



contract FileAccessCollectionUpgradeable is IFileAccessCollectionUpgradeable,
    ERC2981Upgradeable, ERC1155Upgradeable, ERC1155SupplyUpgradeable,
    SignatureAuth, PaidActions, EIP712Upgradeable
{
    bytes32 constant SMintMultipleCallTypeHash = keccak256("SMintMultipleCall(uint256 id,address[] to,uint256[] amounts,uint256 callCost,bytes32 interactionId,address from)");
    bytes32 constant SAddTokenCallTypeHash = keccak256("SAddTokenCall(string slug,uint96 royalties,uint256 tokenMaxSupply,uint256 callCost,bytes32 interactionId,address from)");
    bytes32 constant SMaxSupplyCallTypeHash = keccak256("CMaxSupplyStruct(uint256 tokenId,uint256 tokenMaxSupply,bytes32 interactionId,address from)");

    using ToString for bytes32;
    using ToString for address;

    using az09Dash for string;
    using ECDSAUpgradeable for bytes32;

    string public name;
    string public description;
    uint256 public latestTokenId;

    mapping(uint256 => string) public tokenToFile;
    mapping(string => uint256) public fileToToken;
    mapping(uint256 => uint256) private _maxSupply;

    address public royaltyReceiver;
    // signature stuff
    mapping (bytes32 => bool) public executedMap;
    address private immutable _signer;

    bytes32 immutable private _tokenDomain;
    address immutable private _feeCollector;
    IFileActionCounter public immutable actionCounter;
    address immutable _minter;
    address immutable _listHelper;

    string constant public VERSION = "0.0.2";

    event MaxSupply(uint256 tokenId, uint256 oldMaxSupply, uint256 newMaxSupply);

    event AddToken(uint256 tokenId, string slug);

    constructor(
        string memory tokenDomain_,
        address signer_,
        address feeCollector_,
        address actionCounter_,
        address minter_,
        address listHelper_
    ) {
        _tokenDomain = bytes32(bytes(tokenDomain_));
        _signer = signer_;
        _feeCollector = feeCollector_;
        _minter = minter_;
        _listHelper = listHelper_;
        actionCounter = IFileActionCounter(actionCounter_);
    }

    function maxSupply(uint256 id) public view virtual returns (uint256) {
        return _maxSupply[id];
    }

    function getFeeCollector() public view override returns(address) {
        return _feeCollector;
    }

    // signature stuff
    function signWallet() public view override returns(address) {
        return _signer;
    }

    function isExecuted(bytes32 interactionId) public view override returns (bool) {
        return executedMap[interactionId];
    }

    function initialize(
        address creator, string memory name_, string memory description_
    ) public initializer {
        name = name_;
        description = description_;
        royaltyReceiver = creator;
        __ERC1155_init('');
        __ERC2981_init();
        __EIP712_init("FileAccessCollectionUpgradeable", VERSION);
    }

    function uri(uint256) public view override(IFileAccessCollectionUpgradeable, ERC1155Upgradeable) returns (string memory) {
        return string(abi.encodePacked(
            'https://', _tokenDomain.toString(), '/', address(this).toString(), '/{id}.json'
        ));
    }

    function mintMultiple(
        SMintMultipleCall calldata req,
        bytes memory signature
    ) external payable {
        require (isExecuted(req.interactionId) == false, "Already executed");
        require(req.callCost <= msg.value, "FileAccessCollectionUpgradeable: Underpriced");
        require(verifyMint(req, signature), "INVALID_SIGNATURE");
        require(req.from == _msgSender(), "FileAccessCollectionUpgradeable: Wrong sender");
        executedMap[req.interactionId] = true;

        actionCounter.addTokensMinted(
            _msgSender(),
            _mintMultiple(
                req.to,
                req.id,
                req.amounts
            )
        );

        if(req.callCost > 0) {
            _payFee(msg.value);
        }

    }

    function mint(address to, uint256 id, uint256 amount, bytes memory data) external {
        require(_msgSender() == _minter, "Not allowed");
        _mint(to, id, amount, data);
    }

    function _mintMultiple(
        address[] memory to,
        uint256 id,
        uint256[] memory amounts
    ) private returns(uint256) {
        require(exists(id), 'Token does not exist');
        require(to.length == amounts.length, 'Different array length');

        if (maxSupply(id) > 0) {
            uint256 totalToMint = 0;
            for (uint256 i = 0; i < amounts.length; ++i) {
                totalToMint += amounts[i];
            }

            if ( (totalSupply(id) + totalToMint) > maxSupply(id)) {
                revert("Can't mint more tokens. Max supply exceed.");
            }
        }

        uint256 mintedCount = 0;
        for(uint256 i; i<to.length; i++){
            _mint(to[i], id, amounts[i], "");
            mintedCount += amounts[i];
        }

        return mintedCount;
    }

    function exists(uint256 id) public view override(ERC1155SupplyUpgradeable) returns (bool) {
        return bytes(tokenToFile[id]).length > 0;
    }

    function verifyMaxSupply(SMaxSupplyCall calldata req, bytes memory signature) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(SMaxSupplyCallTypeHash, req.tokenId, req.tokenMaxSupply, req.interactionId, req.from))
        ).recover(signature);

        return signer == signWallet();
    }

    function verifyMint(SMintMultipleCall calldata req, bytes memory signature) public view returns(bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(
                SMintMultipleCallTypeHash, req.id, keccak256(abi.encodePacked(req.to)),
                keccak256(abi.encodePacked(req.amounts)), req.callCost, req.interactionId, req.from
            ))
        ).recover(signature);

        return signer == signWallet();
    }

    function verifyAddToken(SAddTokenCall calldata req, bytes memory signature) public view returns(bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(
                SAddTokenCallTypeHash, keccak256(bytes(req.slug)), req.royalties,
                req.tokenMaxSupply,
                req.callCost, req.interactionId, req.from
            ))
        ).recover(signature);

        return signer == signWallet();
    }

    function addToken(
        SAddTokenCall calldata req,
        bytes memory signature
    ) external payable {
        require (req.callCost <= msg.value, "FileAccessCollectionUpgradeable: Underpriced");
        require (isExecuted(req.interactionId) == false, "FileAccessCollectionUpgradeable: Already executed");
        require (req.from == _msgSender(), "FileAccessCollectionUpgradeable: INVALID_SENDER");
        require (req.slug.isAz09Dash(), "FileAccessCollectionUpgradeable: Slug format mismatch");
        require (verifyAddToken(req, signature), "FileAccessCollectionUpgradeable: INVALID_SIGNATURE");

        executedMap[req.interactionId] = true;

        _addToken(req.slug, req.royalties, req.tokenMaxSupply);

        if(req.callCost > 0) {
            _payFee(msg.value);
        }

        actionCounter.addTokensCreated(_msgSender(), 1);
    }


    function setTokenRoyaltyPercentage(uint256 tokenId, uint96 _royaltyPercentage) external {
        require(
            _msgSender() == _listHelper,
            "Not allowed"
        );
        require(_royaltyPercentage < 10000, "Invalid percentage");

        _setTokenRoyalty(tokenId, royaltyReceiver, _royaltyPercentage);
    }

    function _addToken(string memory fileId, uint96 royalties, uint256 tokenMaxSupply) private {
        require(bytes(fileId).length > 0, 'Empty file id');
        require(fileToToken[fileId] == 0, 'Token already exist');
        latestTokenId = latestTokenId + 1;
        uint256 currentTokenId = latestTokenId;

        tokenToFile[currentTokenId] = fileId;
        fileToToken[fileId] = currentTokenId;
        _setMaxSupply(currentTokenId, tokenMaxSupply);

        if (royaltyReceiver != address(0)) {
            _setTokenRoyalty(currentTokenId, royaltyReceiver, royalties);
        }
        emit TransferSingle(
            _msgSender(),
            address(0),
            address(0),
            currentTokenId,
            0
        );
        emit AddToken(currentTokenId, fileId);
        emit URI(uri(currentTokenId), currentTokenId);
    }

    function setMaxSupply(
        SMaxSupplyCall calldata req,
        bytes memory signature
    ) public {
        require (isExecuted(req.interactionId) == false, "Already executed");
        require (verifyMaxSupply(req, signature), "INVALID_SIGNATURE");
        require(req.from == _msgSender(), "FileAccessCollectionUpgradeable: Wrong sender");

        executedMap[req.interactionId] = true;
        _setMaxSupply(req.tokenId, req.tokenMaxSupply);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155Upgradeable, ERC2981Upgradeable, IERC165Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _setMaxSupply(uint256 tokenId, uint256 tokenMaxSupply) private {
        emit MaxSupply(tokenId, _maxSupply[tokenId], tokenMaxSupply);
        _maxSupply[tokenId] = tokenMaxSupply;
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) {
        ERC1155SupplyUpgradeable._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}