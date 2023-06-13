// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@ghostdrive/signer/sol/contracts/SignatureAuth.sol";
import "../PaidActions.sol";
import "./interfaces/INotesActionCounter.sol";
import { az09Dash } from "../libs/az09Dash.sol";
import { ToString } from "../libs/ToString.sol";

contract NotesCollectionUpgradeable is
    ERC2981Upgradeable, ERC1155Upgradeable, ERC1155SupplyUpgradeable, EIP712Upgradeable,
    SignatureAuth, PaidActions
{
    using ToString for bytes32;
    using ToString for address;

    using az09Dash for string;
    using ECDSAUpgradeable for bytes32;

    string public name;
    uint256 public workspaceId;

    uint256 public latestTokenId;

    // signature stuff
    mapping (bytes32 => bool) public executedMap;
    address private immutable _signer;

    bytes32 immutable private _tokenDomain;
    address immutable private _feeCollector;
    INotesActionCounter public immutable actionCounter;

    address public royaltyReceiver;
    mapping(uint256 => string) public tokenToNote;
    mapping(string => uint256[]) public noteToTokens;

    string constant public VERSION = "0.0.2";

    mapping(uint256 => TokenParams) public tokenParams;

    struct TokenParams {
        bool isTransferable;
        bool isOneTimeView;
    }

    struct SMintMultipleCall {
        uint256 id;
        address[] to;
        uint256[] amounts;
        uint256 callCost;
        bytes32 interactionId;
        address from;
    }

    bytes32 constant SMintMultipleCallTypeHash = keccak256("SMintMultipleCall(uint256 id,address[] to,uint256[] amounts,uint256 callCost,bytes32 interactionId,address from)");

    struct SAddTokenCall {
        string slug;
        uint96 royalties;
        bool isTransferable;
        bool isOneTimeView;
        uint256 callCost;
        bytes32 interactionId;
        address from;
    }

    bytes32 constant SAddTokenCallTypeHash = keccak256("SAddTokenCall(string slug,uint96 royalties,bool isTransferable,bool isOneTimeView,uint256 callCost,bytes32 interactionId,address from)");

    struct CTokenRoyaltyCall {
        uint256 tokenId;
        uint96 fee;
        bytes32 interactionId;
        address from;
    }

    bytes32 constant CTokenRoyaltyCallTypeHash = keccak256("CTokenRoyaltyCall(uint256 tokenId,uint96 fee,bytes32 interactionId,address from)");

    constructor(
        string memory tokenDomain_,
        address signer_,
        address feeCollector_,
        address actionCounter_
    ) {
        _tokenDomain = bytes32(bytes(tokenDomain_));
        _signer = signer_;
        _feeCollector = feeCollector_;
        actionCounter = INotesActionCounter(actionCounter_);
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
        address creator_, string memory name_, uint256 workspaceId_
    ) public initializer {
        name = name_;
        royaltyReceiver = creator_;
        workspaceId = workspaceId_;
        __ERC1155_init('');
        __ERC2981_init();
        __EIP712_init("NotesCollectionUpgradeable", VERSION);
    }

    function uri(uint256) public view override returns (string memory) {
        return string(abi.encodePacked(
            'https://', _tokenDomain.toString(), '/', address(this).toString(), '/{id}.json'
        ));
    }

    function domainSeparator() public view returns(bytes32) {
        return _domainSeparatorV4();
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

    function mintMultiple(
        SMintMultipleCall calldata req,
        bytes memory signature
    ) external payable  {
        require (isExecuted(req.interactionId) == false, "Already executed");
        require(req.callCost <= msg.value, "Underpriced");
        require(req.from == _msgSender(), "Wrong sender");
        require(verifyMint(req, signature), "INVALID_SIGNATURE");
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

    function _mintMultiple(
        address[] memory to,
        uint256 id,
        uint256[] memory amounts
    ) private returns(uint64) {
        require(bytes(tokenToNote[id]).length > 0, 'Token does not exist');
        require(to.length == amounts.length, 'Different array length');
        uint64 total;
        for(uint256 i; i<to.length; i++){
            total += uint64(amounts[i]);
            _mint(to[i], id, amounts[i], "");
        }

        return total;
    }

    function burn(
        address account,
        uint256 id,
        uint256 value
    ) public  {
        require(tokenParams[id].isOneTimeView, "NotesCollectionUpgradeable: Not a one-time-view token could not be burned");
        require(
            account == _msgSender() || isApprovedForAll(account, _msgSender()),
            "NotesCollectionUpgradeable: caller is not token owner nor approved"
        );
        _burn(account, id, value);
    }

    function verifyAddToken(SAddTokenCall calldata req, bytes memory signature) public view returns(bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(
                SAddTokenCallTypeHash, keccak256(bytes(req.slug)), req.royalties,
                req.isTransferable, req.isOneTimeView,
                req.callCost, req.interactionId, req.from
            ))
        ).recover(signature);

        return signer == signWallet();
    }

    function addToken(
        SAddTokenCall calldata req,
        bytes memory signature
    ) external payable {
        require (req.callCost <= msg.value, "Underpriced");
        require (isExecuted(req.interactionId) == false, "NotesCollectionUpgradeable: Already executed");
        require (req.from == _msgSender(), "NotesCollectionUpgradeable: INVALID_SENDER");
        require (req.slug.isAz09Dash(), "NotesCollectionUpgradeable: Slug format mismatch");

        require(verifyAddToken(req, signature), "NotesCollectionUpgradeable: INVALID_SIGNATURE");

        executedMap[req.interactionId] = true;

        _addToken(req.slug, req.isTransferable, req.isOneTimeView);

        if (royaltyReceiver != address(0)) {
            _setTokenRoyalty(latestTokenId, royaltyReceiver, req.royalties);
        }

        if(req.callCost > 0) {
            _payFee(msg.value);
        }

        actionCounter.addTokensCreated(_msgSender(), 1);
    }

    function _addToken(string memory slug, bool _isTransferable, bool _isOneTimeView) private {

        for(uint256 i = 0; i < noteToTokens[slug].length; i++) {
            uint256 existingTokenId = noteToTokens[slug][i];
            require(
                (
                tokenParams[existingTokenId].isTransferable != _isTransferable
                    || tokenParams[existingTokenId].isOneTimeView != _isOneTimeView
                ),
                "Token for this file with such options already exists"
            );
        }

        uint256 newTokenId = latestTokenId + 1;
        tokenToNote[newTokenId] = slug;

        noteToTokens[slug].push(newTokenId);
        tokenParams[newTokenId].isTransferable = _isTransferable;
        tokenParams[newTokenId].isOneTimeView = _isOneTimeView;

        emit TransferSingle(
            _msgSender(),
            address(0),
            address(0),
                newTokenId,
            0
        );

        latestTokenId = newTokenId;

        emit URI(uri(newTokenId), newTokenId);
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

    function verifyRoyalty(CTokenRoyaltyCall calldata req, bytes memory signature) public view returns(bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(CTokenRoyaltyCallTypeHash, req.tokenId, req.fee, req.interactionId, req.from))
        ).recover(signature);

        return signer == signWallet();
    }

    function setTokenRoyalty(
        CTokenRoyaltyCall calldata req,
        bytes memory signature
    ) public {
        require (royaltyReceiver != address(0), "Unknown royalty receiver");
        require (isExecuted(req.interactionId) == false, "Already executed");
        require (req.from == _msgSender(), "NotesCollectionUpgradeable: INVALID_SENDER");
        require(verifyRoyalty(req, signature), "NotesCollectionUpgradeable: INVALID_SIGNATURE");

        executedMap[req.interactionId] = true;
        _setTokenRoyalty(req.tokenId, royaltyReceiver, req.fee);
    }


    function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC1155Upgradeable, ERC2981Upgradeable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        require(
            tokenParams[id].isTransferable,
            "NotesCollectionUpgradeable: non-transferable"
        );
        super.safeTransferFrom(from, to, id, amount, data);
    }

}