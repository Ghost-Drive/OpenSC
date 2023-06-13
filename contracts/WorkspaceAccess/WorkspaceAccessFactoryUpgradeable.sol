// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@ghostdrive/signer/sol/contracts/SignatureAuth.sol";
import "./interfaces/IWorkspaceAccessUpgradeable.sol";
import "../PaidActions.sol";


contract WorkspaceAccessFactoryUpgradeable
    is OwnableUpgradeable, EIP712Upgradeable, SignatureAuth, PaidActions
{
    using ECDSAUpgradeable for bytes32;

    struct SNewWSAccessCall {
        uint256 workspaceId;
        uint256 accessCost;
        uint256 fee;
        bytes32 interactionId;
        address from;
    }

    bytes32 constant public SNewWSAccessCallTypeHash =
        keccak256("SNewWSAccessCall(uint256 workspaceId,uint256 accessCost,uint256 fee,bytes32 interactionId,address from)");

    address[] public contractsAddresses;

    mapping(uint256 => address) workspaceAccessContracts;

    address public accessBeacon;

    // signature stuff
    mapping (bytes32 => bool) public executedMap;

    mapping (address => bool) public isWorkspaceAccessContract;

    address private immutable _signer;

    address immutable private _feeCollector;

    string constant public VERSION = "0.0.2";

    event AddNewWorkspaceAccessContract(address contractAddress, uint256 workspaceId);

    constructor(address signer_, address feeCollector_) {
        _signer = signer_;
        _feeCollector = feeCollector_;
    }

    function initialize(address accessBeacon_) public initializer {
        accessBeacon = accessBeacon_;
        __Ownable_init();
        __EIP712_init("WorkspaceAccessFactoryUpgradeable", VERSION);
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

    function verify(SNewWSAccessCall calldata req, bytes memory signature) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(
                SNewWSAccessCallTypeHash, req.workspaceId, req.accessCost,
                req.fee, req.interactionId, req.from
            ))
        ).recover(signature);

        return signer == signWallet();
    }

    function newWorkspaceAccessContract(
        SNewWSAccessCall calldata req,
        bytes memory signature
    ) public payable returns(address) {
        require (workspaceAccessContracts[req.workspaceId] == address(0), "WorkspaceAccessFactoryUpgradeable: Already exists");
        require (isExecuted(req.interactionId) == false, "WorkspaceAccessFactoryUpgradeable: Already executed");
        require (verify(req, signature), "WorkspaceAccessFactoryUpgradeable: INVALID_SIGNATURE");
        require (req.from == _msgSender(), "WorkspaceAccessFactoryUpgradeable: Wrong sender");
        require (msg.value >= req.fee, "WorkspaceAccessFactoryUpgradeable: too less");

        executedMap[req.interactionId] = true;
        BeaconProxy proxy = new BeaconProxy (
            accessBeacon,
            abi.encodeWithSelector(
                IWorkspaceAccessUpgradeable(address(0)).initialize.selector,
                _msgSender(),
                req.accessCost,
                req.workspaceId
            )
        );

        address proxyAddress = address(proxy);
        workspaceAccessContracts[req.workspaceId] = proxyAddress;
        contractsAddresses.push(proxyAddress);

        if(req.fee > 0) {
            _payFee(msg.value);
        }

        isWorkspaceAccessContract[proxyAddress] = true;
        emit AddNewWorkspaceAccessContract(proxyAddress, req.workspaceId);
        return proxyAddress;
    }

    function getWorkspaceAccessContract(uint256 workspaceId) public view returns(address){
        return workspaceAccessContracts[workspaceId];
    }
}