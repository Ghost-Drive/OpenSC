// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "./interfaces/INotesActionCounter.sol";
import "./interfaces/INotesCollectionUpgradeable.sol";
import "../PaidActions.sol";
import {Az09Space} from "../libs/Az09Space.sol";

contract NotesCollectionFactoryUpgradeable
is PaidActions, EIP712Upgradeable, INotesActionCounter, ContextUpgradeable
{
    using Az09Space for string;
    using ECDSAUpgradeable for bytes32;

    struct UsageCounter {
        uint64 tokensMintedCount;
        uint64 tokensCreatedCount;
        uint64 tokensContractsCreatedCount;
    }
    
    address[] contractsAddresses;

    mapping(uint256 => address) notesContracts;

    address public accessBeacon;

    // signature stuff
    mapping (bytes32 => bool) public executedMap;

    mapping (address => bool) public isNotesContract;

    mapping (address => UsageCounter) public usage;

    address private immutable _signer;

    address immutable private _feeCollector;

    string constant public VERSION = "0.0.2";

    struct SNewNoteContractCall {
        uint256 workspaceId;
        string name;
        uint256 callCost;
        bytes32 interactionId;
        address from;
    }

    bytes32 constant SNewNoteContractCallTypeHash =
        keccak256("SNewNoteContractCall(uint256 workspaceId,string name,uint256 callCost,bytes32 interactionId,address from)");


    event AddNewNoteContract (address contractAddress, uint256 workspaceId);

    constructor(address signer_, address feeCollector_) {
        _signer = signer_;
        _feeCollector = feeCollector_;
    }

    function initialize(address accessBeacon_) public initializer {
        accessBeacon = accessBeacon_;
        __Context_init();
        __EIP712_init("NotesCollectionFactoryUpgradeable", VERSION);
    }

    function verify(SNewNoteContractCall calldata req, bytes memory signature) public view returns(bool) {
        address signer = _hashTypedDataV4(
            keccak256(abi.encode(
                SNewNoteContractCallTypeHash, req.workspaceId, keccak256(bytes(req.name)), req.callCost, req.interactionId, req.from
            ))
        ).recover(signature);

        return signer == signWallet();
    }

    function getFeeCollector() public view override returns(address) {
        return _feeCollector;
    }

    function signWallet() public view returns(address) {
        return _signer;
    }

    function isExecuted(bytes32 interactionId) public view returns (bool) {
        return executedMap[interactionId];
    }

    function newNoteContract(
        SNewNoteContractCall calldata req,
        bytes memory signature
    ) public payable returns(address) {
        require (isExecuted(req.interactionId) == false, "NotesContractFactoryUpgradeable: Already executed");
        require (notesContracts[req.workspaceId] == address(0), "NotesContractFactoryUpgradeable: Already exists");
        require(_msgSender() == req.from, "NotesContractFactoryUpgradeable: INVALID_SENDER");
        require(req.callCost <= msg.value, "NotesContractFactoryUpgradeable: Underpriced");
        require(req.name.isAZ09Space(), "Name may contain alphanumeric characters and a space");
        require(req.from == _msgSender(), "Wrong sender");
        require(verify(req, signature), "NotesContractFactoryUpgradeable: INVALID_SIGNATURE");

        executedMap[req.interactionId] = true;

        BeaconProxy proxy = new BeaconProxy (
            accessBeacon,
            abi.encodeWithSelector(
                INotesCollectionUpgradeable(address(0)).initialize.selector,
                _msgSender(),
                req.name,
                req.workspaceId
            )
        );

        address proxyAddress = address(proxy);
        notesContracts[req.workspaceId] = proxyAddress;
        contractsAddresses.push(proxyAddress);

        if(req.callCost > 0) {
            _payFee(msg.value);
        }
        usage[req.from].tokensContractsCreatedCount = usage[req.from].tokensContractsCreatedCount + 1;
        isNotesContract[proxyAddress] = true;
        emit AddNewNoteContract(proxyAddress, req.workspaceId);
        return proxyAddress;
    }

    function getWorkspaceNoteContract(uint256 workspaceId) public view returns(address){
        return notesContracts[workspaceId];
    }

    function addTokensMinted(address user, uint64 minted) external {
        require(isNotesContract[_msgSender()], "Not authorized to increment tokensMintedCount");
        usage[user].tokensMintedCount = usage[user].tokensMintedCount + minted;
    }

    function addTokensCreated(address user, uint64 created) external {
        require(isNotesContract[_msgSender()], "Not authorized to increment tokensCreatedCount");
        usage[user].tokensCreatedCount = usage[user].tokensCreatedCount + created;
    }
}