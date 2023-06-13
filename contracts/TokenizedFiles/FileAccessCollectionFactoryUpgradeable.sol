// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@ghostdrive/signer/sol/contracts/SignatureAuth.sol";
import "../PaidActions.sol";
import {Az09Space} from "../libs/Az09Space.sol";

import "./interfaces/IFileAccessCollectionUpgradeable.sol";
import "./interfaces/IFileActionCounter.sol";



contract FileAccessCollectionFactoryUpgradeable
    is OwnableUpgradeable, SignatureAuth, PaidActions, EIP712Upgradeable, IFileActionCounter
{
    using Az09Space for string;
    using ECDSAUpgradeable for bytes32;

    address[] contractsAddresses;

    mapping(uint256 => address[]) workspaceCollections;

    address public tokenBeacon;

    // signature stuff
    mapping (bytes32 => bool) public executedMap;

    mapping (address => bool) public isFileAccessContract;

    mapping (address => uint256) public tokensMintedCount;
    mapping (address => uint256) public tokensCreatedCount;
    mapping (address => uint256) public tokensContractsCreatedCount;


    address private immutable _signer;

    address immutable private _feeCollector;

    string constant public VERSION = "0.0.2";

    struct SNewFileACCall {
        uint256 workspaceId;
        string name;
        string description;
        uint256 callCost;
        bytes32 interactionId;
        address from;
    }

    bytes32 constant public SNewFileACCallTypeHash =
        keccak256("SNewFileACCall(uint256 workspaceId,string name,string description,uint256 callCost,bytes32 interactionId,address from)");

    event AddNewFileAccessContract (address contractAddress, uint256 workspaceId, string name, string description);

    constructor(address signer_, address feeCollector_) {
        _signer = signer_;
        _feeCollector = feeCollector_;
    }

    function domainSeparator() public view returns (bytes32) { // debug purpose
        return super._domainSeparatorV4();
    }

    function initialize(address tokenBeacon_) public initializer {
        tokenBeacon = tokenBeacon_;
        __EIP712_init("FileAccessCollectionFactoryUpgradeable", VERSION);
        __Context_init();
    }

    function addTokensMinted(address user, uint256 minted) external {
        require(isFileAccessContract[_msgSender()], "Not authorized to increment tokensMintedCount");
        tokensMintedCount[user] = tokensMintedCount[user] + minted;
    }

    function addTokensCreated(address user, uint256 created) external {
        require(isFileAccessContract[_msgSender()], "Not authorized to increment tokensCreatedCount");
        tokensCreatedCount[user] = tokensCreatedCount[user] + created;
    }

    function getFeeCollector() public view override returns(address) {
        return _feeCollector;
    }

    function signWallet() public view override returns(address) {
        return _signer;
    }

    function isExecuted(bytes32 interactionId) public view override returns (bool) {
        return executedMap[interactionId];
    }

    function getFileAccessContractsCountWS(uint256  workspaceId) public view returns(uint256 count) {
        return workspaceCollections[workspaceId].length;
    }

    function verify(SNewFileACCall calldata req, bytes calldata signature) public view returns (bool){
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(
                SNewFileACCallTypeHash, req.workspaceId, keccak256(bytes(req.name)),
                keccak256(bytes(req.description)), req.callCost, req.interactionId, req.from
            ))
        ).recover(signature);

        return signer == signWallet();
    }

    function newFileAccessContract(
        SNewFileACCall calldata req,
        bytes calldata signature
    ) public payable returns(address) {
        // @todo make sure unique name of collection within workspace
        require(isExecuted(req.interactionId) == false, "Already executed");
        require(verify(req, signature), "INVALID_SIGNATURE");
        require(req.callCost <= msg.value, "FileAccessCollectionFactoryUpgradeable: Underpriced");
        require(req.name.isAZ09Space(), "Name can contain alphanumeric characters and space only");
        require(req.from == _msgSender(), "FileAccessCollectionFactoryUpgradeable: Wrong sender");
        require(
            bytes(req.description).length == 0 || req.description.isAZ09Space(),
            "Description can contain alphanumeric characters and space only"
        );

        executedMap[req.interactionId] = true;

        BeaconProxy proxy = new BeaconProxy(
            tokenBeacon,
            abi.encodeWithSelector(
                IFileAccessCollectionUpgradeable(address(0)).initialize.selector,
                _msgSender(),
                req.name,
                req.description
            )
        );

        address proxyAddress = address(proxy);
        workspaceCollections[req.workspaceId].push(proxyAddress);
        contractsAddresses.push(proxyAddress);

        if(req.callCost > 0) {
            _payFee(msg.value);
        }

        isFileAccessContract[proxyAddress] = true;
        tokensContractsCreatedCount[_msgSender()]++;
        emit AddNewFileAccessContract(proxyAddress, req.workspaceId, req.name, req.description);
        return proxyAddress;
    }

    function getFileAccessContracts(uint256 workspaceId) public view returns(address[] memory){
        return workspaceCollections[workspaceId];
    }
}