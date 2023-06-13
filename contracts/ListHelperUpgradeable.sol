pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "./TokenizedFiles/interfaces/IFileAccessCollectionUpgradeable.sol";
import "./libs/IGhostMinter.sol";
import "./libs/IRegistry.sol";
import "@ghostdrive/signer/sol/contracts/SignatureAuth.sol";

contract ListHelperUpgradeable is EIP712Upgradeable, SignatureAuth
{
    using ECDSAUpgradeable for bytes32;

    struct SListTokenCall {
        address tokenAddress;
        uint256 tokenId;
        uint96 royalties;
        bytes32 interactionId;
        address from;
    }

    bytes32 constant public SListTokenCallTypeHash = keccak256("SListTokenCall(address tokenAddress,uint256 tokenId,uint96 royalties,bytes32 interactionId,address from)");

    string constant public VERSION = "0.0.2";

    IRegistry immutable _registry;

    // signature stuff
    address private immutable _signer;
    mapping (bytes32 => bool) public executedMap;


    event TokenListed(address tokenAddress, uint256 tokenId);

    constructor(
        address registry_,
        address signer_
    ) {
        _registry = IRegistry(registry_);
        _signer = signer_;
    }

    function initialize() public initializer {
        __EIP712_init("ListHelperUpgradeable", VERSION);
    }

    function domainSeparator() public view returns (bytes32) { // debug purpose
        return super._domainSeparatorV4();
    }

    function domainSeparatorV4() public view returns (bytes32) { // debug purpose
        return super._domainSeparatorV4();
    }

    function listFileToken(SListTokenCall calldata req, bytes memory signature) external {
        require(verifyListTokenCall(req, signature), "ListHelperUpgradeable: INVALID_SIGNATURE");

        // @todo verify if contract is our file token
        // add our nft to registry if it is not there yet
        bytes32 contractName = bytes32(bytes20(req.tokenAddress));
        bool hasContract = _registry.hasContract(contractName);

        if (!hasContract) {
            _registry.addContract(contractName, req.tokenAddress);
        }

        // set new royalties value to token
        IFileAccessCollectionUpgradeable token = IFileAccessCollectionUpgradeable(req.tokenAddress);

        token.setTokenRoyaltyPercentage(req.tokenId, req.royalties);

        emit TokenListed(req.tokenAddress, req.tokenId);
    }


    function verifyListTokenCall(SListTokenCall calldata req, bytes memory signature) public view returns(bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(
                SListTokenCallTypeHash, req.tokenAddress, req.tokenId, req.royalties, req.interactionId, req.from
            ))
        ).recover(signature);

        return signer == signWallet();
    }

    // signature stuff
    function signWallet() public view override returns(address) {
        return _signer;
    }

    function isExecuted(bytes32 interactionId) public view override returns (bool) {
        return executedMap[interactionId];
    }

}