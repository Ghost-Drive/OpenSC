// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@ghostdrive/signer/sol/contracts/SignatureAuth.sol";
import "../PaidActions.sol";
import "./WorkspaceMultisigUpgradeable.sol";

contract WorkspaceMultisigFactoryUpgradeable
    is  ContextUpgradeable, EIP712Upgradeable, SignatureAuth, PaidActions
{
    using ECDSAUpgradeable for bytes32;

    struct SNewMultisigCall {
        uint256 workspaceId;
        uint8 requiredSignatures;
        address[] initialParticipants;
        uint256 callCost;
        bytes32 interactionId;
        address from;
    }

    bytes32 constant public SNewMultisigCallTypeHash =
    keccak256("SNewMultisigCall(uint256 workspaceId,uint8 requiredSignatures,address[] initialParticipants,uint256 callCost,bytes32 interactionId,address from)");
    mapping (bytes32 => bool) public executedMap;
    mapping (address => bool) public isWorkspaceMultisigContract;
    address private immutable _signer;
    address immutable private _feeCollector;
    string constant public VERSION = "0.0.2";


    mapping(uint256 => address) workspaceMultisigContracts;
    address public multisigBeacon;


    event AddNewWorkspaceMultisigContract(address contractAddress, uint256 workspaceId);

    constructor(address signer_, address feeCollector_) {
        _signer = signer_;
        _feeCollector = feeCollector_;
    }

    function initialize(address multisigBeacon_) public initializer {
        multisigBeacon = multisigBeacon_;
        __EIP712_init("WorkspaceMultisigFactoryUpgradeable", VERSION);
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

    // Rest of the functions from previous code
    function newWorkspaceMultisigContract(
        SNewMultisigCall calldata req,
        bytes memory signature
    ) public payable returns(address) {
        require(workspaceMultisigContracts[req.workspaceId] == address(0), "WorkspaceMultisigFactoryUpgradeable: Already exists");
        require(isExecuted(req.interactionId) == false, "WorkspaceMultisigFactoryUpgradeable: Already executed");
        require(verify(req, signature), "WorkspaceMultisigFactoryUpgradeable: INVALID_SIGNATURE");
        require(req.from == _msgSender(), "WorkspaceMultisigFactoryUpgradeable: Wrong sender");
        require(msg.value >= req.callCost, "WorkspaceMultisigFactoryUpgradeable: Insufficient fee");

        BeaconProxy proxy = new BeaconProxy(
            multisigBeacon,
            abi.encodeWithSelector(
                WorkspaceMultisigUpgradeable(address(0)).initialize.selector,
                req.workspaceId,
                req.requiredSignatures,
                req.initialParticipants
            )
        );

        address proxyAddress = address(proxy);
        workspaceMultisigContracts[req.workspaceId] = proxyAddress;

        if(req.callCost > 0) {
            _payFee(msg.value);
        }

        emit AddNewWorkspaceMultisigContract(proxyAddress, req.workspaceId);
        return proxyAddress;
    }

    function getWorkspaceMultisigContract(uint256 workspaceId) public view returns(address){
        return workspaceMultisigContracts[workspaceId];
    }

    function verify(SNewMultisigCall calldata req, bytes memory signature) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(
                SNewMultisigCallTypeHash,
                req.workspaceId,
                req.requiredSignatures,
                keccak256(abi.encodePacked(req.initialParticipants)),
                req.callCost,
                req.interactionId,
                req.from
            ))
        ).recover(signature);

        return signer == signWallet();
    }

    function domainSeparator() public view returns (bytes32) { // debug purpose
        return super._domainSeparatorV4();
    }
}