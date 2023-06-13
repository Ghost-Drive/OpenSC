// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@ghostdrive/signer/sol/contracts/SignatureAuth.sol";
import "./interfaces/IWorkspaceAccessUpgradeable.sol";
import "../PaidActions.sol";
import "hardhat/console.sol";


contract WorkspaceAccessUpgradeable is
    IWorkspaceAccessUpgradeable,
    EIP712Upgradeable,
    ContextUpgradeable,
    SignatureAuth,
    PaidActions
{

    using ECDSAUpgradeable for bytes32;

    address public beneficiary;
    uint256 public accessCost;
    uint256 public workspaceId;

    mapping (uint8 => bool) public planIsActive;
    mapping (address => uint256) public accessPaidAt;

    // signature stuff
    mapping (bytes32 => bool) public executedMap;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address immutable private _signer;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address immutable private  _feeCollector;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    uint256 immutable private _feePercentage;

    event AccessCost(uint8 plan, uint256 accessCost);
    event AccessPaid(uint8 plan, uint256 amountPaid, address user, uint256 expireAt);
    event PlanIsActive(uint8 plan, bool isActive);

    struct SSetCostCall {
        uint8 plan;
        uint256 accessCost;
        bytes32 interactionId;
        address from;
    }

    bytes32 constant public SSetCostCallTypeHash = keccak256("SSetCostCall(uint8 plan,uint256 accessCost,bytes32 interactionId,address from)");

    struct SPlanActivationCall {
        uint8 plan;
        bool isActive;
        bytes32 interactionId;
        address from;
    }

    bytes32 constant SPlanActivationCallTypeHash = keccak256("SPlanActivationCall(uint8 plan,bool isActive,bytes32 interactionId,address from)");

    string constant public VERSION = "0.0.2";

    constructor(
        address signer_,
        uint256 feePercentage_,
        address feeCollector_
    ) {
        _signer = signer_;
        _feePercentage = feePercentage_;
        _feeCollector = feeCollector_;
    }

    function initialize(
        address beneficiary_, uint256 accessCost_, uint256 workspaceId_
    ) public initializer {
        beneficiary = beneficiary_;
        accessCost = accessCost_;
        workspaceId = workspaceId_;
        planIsActive[1] = true;
        __Context_init();
        __EIP712_init("WorkspaceAccessUpgradeable", VERSION);
    }

    function getFeeCollector() public view override returns(address) {
        return _feeCollector;
    }

    // signature stuff
    function signWallet() public view override returns(address) {
        return _signer;
    }

    function getFeePercentage() public view returns(uint256) {
        return _feePercentage;
    }

    function isExecuted(bytes32 interactionId) public view override returns (bool) {
        return executedMap[interactionId];
    }

    function verifySetCostCall(SSetCostCall calldata req, bytes memory signature) public view returns(bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(
                SSetCostCallTypeHash, req.plan, req.accessCost, req.interactionId, req.from
            ))
        ).recover(signature);

        return signer == signWallet();
    }

    function setCost(
        SSetCostCall calldata req, bytes memory signature
    ) public {
        require(isExecuted(req.interactionId) == false, "WorkspaceAccessUpgradeable: Already executed");
        require(req.plan == 1, "WorkspaceAccessUpgradeable: Only plan = 1 currently supported");
        require(req.from == _msgSender(), "WorkspaceAccessUpgradeable: Wrong sender");
        require(verifySetCostCall(req, signature), "WorkspaceAccessUpgradeable: INVALID_SIGNATURE");

        executedMap[req.interactionId] = true;
        _setCost(req.plan, req.accessCost);
    }

    function getCost(uint8 plan) public view returns(uint256) {
        return accessCost;
    }

    function hasAccessBatch(address[] memory accounts)
        public view returns (bool[] memory) {

        bool[] memory batchAccess = new bool[](accounts.length);

        for (uint256 i = 0; i < accounts.length; ++i) {
            batchAccess[i] = accessPaidAt[accounts[i]] > 0;
        }

        return batchAccess;
    }

    function pay(uint8 plan) public payable {
        require(planIsActive[plan], "Deactivated");
        require(msg.value >= accessCost, "Not enough");

        (bool sent, bytes memory data) = beneficiary.call{value: msg.value}("");
        require(sent, "Failed to send to beneficiary");
        accessPaidAt[_msgSender()] = block.timestamp;
        emit AccessPaid(plan, msg.value, _msgSender(), 0);
    }

    function verifyPlanActivationCall(SPlanActivationCall calldata req, bytes memory signature) public view returns(bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(
                SPlanActivationCallTypeHash, req.plan, req.isActive,
                req.interactionId, req.from
            ))
        ).recover(signature);

        return signer == signWallet();
    }

    function planActivation(SPlanActivationCall calldata req, bytes memory signature) public  {
        require (isExecuted(req.interactionId) == false, "WorkspaceAccessUpgradeable: Already executed");
        require (verifyPlanActivationCall(req, signature), "WorkspaceAccessUpgradeable: INVALID_SIGNATURE");
        require (req.from == _msgSender(), "WorkspaceAccessUpgradeable: Wrong sender");
        executedMap[req.interactionId] = true;
        planIsActive[req.plan] = req.isActive;
        emit PlanIsActive(req.plan, req.isActive);
    }

    function _setCost(uint8 plan, uint256 accessCost_) private {
        accessCost = accessCost_;
        emit AccessCost(plan, accessCost);
    }
}