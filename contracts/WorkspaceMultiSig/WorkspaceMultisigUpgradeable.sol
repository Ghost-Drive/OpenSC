// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract WorkspaceMultisigUpgradeable is ContextUpgradeable {

    using Strings for uint256;

    struct Participant {
        address wallet;
        bool exists;
    }

    struct SigningSchema {
        uint8 requiredParticipants;
        uint256 totalParticipants;
        mapping(address => Participant) participants;
        address[] participantList;
    }

    struct Action {
        uint256 actionId;
        bytes32 actionHash;
        ActionType actionType;
        mapping(address => ParticipantStatus) participantStatuses;
        uint8 acceptedCount;
        uint8 declinedCount;
        uint8 pendingCount;
        ActionStatus actionStatus;
        address creator;
        uint256 createdAt;
        uint256 acceptedAt;
        uint256 declinedAt;
        bool exists;
        bytes data;
    }

    enum ParticipantStatus {
        PENDING,
        ACCEPTED,
        DECLINED
    }

    enum ActionStatus {
        PENDING,
        ACCEPTED,
        DECLINED
    }

    enum ActionType {
        AddParticipant,
        ChangeParticipantsRequired,
        RemoveParticipant,
        ShareFileByEmail,
        ShareFileByWallet,
        ShareFileByPublic,
        DeleteFile,
        SafetyNetByEmail,
        SafetyNetByWallet
    }

    event ActionUpdated(
        uint256 indexed actionId, bytes32 indexed actionHash, ActionStatus actionStatus,
        uint8 acceptedCount, uint8 declinedCount, uint8 pendingCount
    );

    uint256 public nextActionId;
    uint256 public workspaceId;
    mapping(bytes32 => uint256) public pendingActionByHash;

    SigningSchema private _signingSchema;
    mapping(uint256 => Action) private _actions;

    // Mapping to store file access by wallet address
    mapping(bytes32 => mapping(address => bool)) private fileAccessByWallet;
    // Mapping to store file access by email
    mapping(bytes32 => mapping(bytes32 => bool)) private fileAccessByEmail;
    // Mapping to store deleted files
    mapping(bytes32 => bool) private fileIsDeleted;

    // Initializer function for upgradeable deployments
    function initialize(
        uint256 workspaceId_,
        uint8 requiredParticipants_,
        address[] memory initialParticipants_
    ) public initializer {
        require(initialParticipants_.length > 0, "WorkspaceMultiSigUpgradeable: should have at least 1 participant");
        require(requiredParticipants_ > 0, "WorkspaceMultiSigUpgradeable: should require at least 1 participant");

        require(
            requiredParticipants_ <= initialParticipants_.length,
            "WorkspaceMultiSigUpgradeable: required signatures must be less than or equal to the number of participants"
        );

        workspaceId = workspaceId_;

        _signingSchema.requiredParticipants = requiredParticipants_;

        for (uint256 i = 0; i < initialParticipants_.length; i++) {
            _addParticipant(initialParticipants_[i]);
        }

        nextActionId = 1;
    }


    function _addParticipant(address newParticipant) internal {
        require(
            !_signingSchema.participants[newParticipant].exists,
            "WorkspaceMultiSigUpgradeable: participant already exists"
        );
        _signingSchema.totalParticipants += 1;
        _signingSchema.participants[newParticipant] = Participant(
            newParticipant,
            true
        );
        _signingSchema.participantList.push(newParticipant);
    }

    function _removeParticipant(address participantToRemove) internal {
        require(
            _signingSchema.participants[participantToRemove].exists,
            "WorkspaceMultiSigUpgradeable: participant does not exist"
        );

        require(
            _signingSchema.requiredParticipants <= (_signingSchema.totalParticipants - 1),
            "WorkspaceMultiSigUpgradeable: removing participant would reduce total participants below required signatures"
        );
        _signingSchema.totalParticipants -= 1;
        _signingSchema.participants[participantToRemove].exists = false;
    }

    function _changeRequiredParticipants(uint8 requiredParticipants) internal {
        require(
            requiredParticipants <= _signingSchema.requiredParticipants,
            "WorkspaceMultiSigUpgradeable: required signatures must be less than or equal to the number of participants"
        );
        require(requiredParticipants > 0, "Should have at least 1 signer");

        _signingSchema.requiredParticipants = requiredParticipants;
    }

    function currentParticipants() public view returns (address[] memory currentParticipants) {
        currentParticipants = new address[](_signingSchema.participantList.length);
        uint256 count = 0;

        for (uint256 i = 0; i < _signingSchema.participantList.length; i++) {
            address participantAddress = _signingSchema.participantList[i];

            if (_signingSchema.participants[participantAddress].exists) {
                currentParticipants[count] = participantAddress;
                count++;
            }
        }

        // Resize the activeParticipants  array to exclude empty slots
        assembly {
            mstore(currentParticipants, count)
        }
    }

    function addParticipant(address participant) external onlyParticipant returns (uint256 actionId) {
        require(
            !_signingSchema.participants[participant].exists,
            'WorkspaceMultiSigUpgradeable: participant already exists'
        );

        bytes memory data = abi.encode(participant);
        bytes32 actionHash = keccak256(abi.encodePacked('addParticipant', data));
        uint256 pendingActionId = pendingActionByHash[actionHash];
        require(
            pendingActionId == 0,
            string(abi.encodePacked("Action already pending: ", pendingActionId.toString()))
        );

        actionId = _createAction(actionHash, ActionType.AddParticipant, data);
        _acceptAction(actionId);
    }

    function removeParticipant(address participant) external onlyParticipant returns (uint256 actionId) {
        require(
            _signingSchema.requiredParticipants <= (_signingSchema.totalParticipants - 1),
            "WorkspaceMultiSigUpgradeable: removing participant would reduce total participants below required signatures"
        );
        require(
            _signingSchema.participants[participant].exists,
            'WorkspaceMultiSigUpgradeable: participant does not exist'
        );

        bytes memory data = abi.encode(participant);
        bytes32 actionHash = keccak256(abi.encodePacked('removeParticipant', data));
        uint256 pendingActionId = pendingActionByHash[actionHash];
        require(
            pendingActionId == 0,
            string(abi.encodePacked("Action already pending: ", pendingActionId.toString()))
        );

        actionId = _createAction(actionHash, ActionType.RemoveParticipant, data);
        _acceptAction(actionId);
    }

    // Function to change the required number of signatures
    function changeParticipantsRequired(uint256 participantsRequired) external onlyParticipant returns (uint256 actionId) {
        bytes32 actionHash = keccak256(abi.encode('changeParticipantsRequired'));
        uint256 pendingActionId = pendingActionByHash[actionHash];
        require(
            pendingActionId == 0,
            string(abi.encodePacked("Action already pending: ", pendingActionId.toString()))
        );

        actionId = _createAction(actionHash, ActionType.ChangeParticipantsRequired, abi.encode(participantsRequired));
        _acceptAction(actionId);
    }


    // Sharing a file by file slug and recipient's wallet address
    function shareFileByWallet(bytes32 fileSlug, address recipientAddress)
    external
    onlyParticipant returns (uint256 actionId)
    {
        bytes memory data = abi.encode(fileSlug, recipientAddress);
        bytes32 actionHash = keccak256(abi.encodePacked('shareFileByWallet', data));
        uint256 pendingActionId = pendingActionByHash[actionHash];
        require(
            pendingActionId == 0,
            string(abi.encodePacked("Action already pending: ", pendingActionId.toString()))
        );
        actionId = _createAction(actionHash, ActionType.ShareFileByWallet, data);
        _acceptAction(actionId);
    }

    function shareFileByEmail(bytes32 fileSlug, bytes32 emailHash)
    external
    onlyParticipant returns (uint256 actionId)
    {
        bytes memory data = abi.encode(fileSlug, emailHash);
        bytes32 actionHash = keccak256(abi.encodePacked('shareFileByEmail', data));
        uint256 pendingActionId = pendingActionByHash[actionHash];
        require(
            pendingActionId == 0,
            string(abi.encodePacked("Action already pending: ", pendingActionId.toString()))
        );

        actionId = _createAction(actionHash, ActionType.ShareFileByEmail, data);
        _acceptAction(actionId);
    }

    // Sharing a file by file slug via public link
    function shareFilePublic(bytes32 fileSlug) external onlyParticipant returns (uint256 actionId) {
        bytes memory data = abi.encode(fileSlug);
        bytes32 actionHash = keccak256(abi.encodePacked('shareFilePublic', data));
        uint256 pendingActionId = pendingActionByHash[actionHash];
        require(
            pendingActionId == 0,
            string(abi.encodePacked("Action already pending: ", pendingActionId.toString()))
        );
        actionId = _createAction(actionHash, ActionType.ShareFileByPublic, data);
        _acceptAction(actionId);
    }

    // Deleting a file by file slug
    function deleteFile(bytes32 fileSlug) external onlyParticipant returns (uint256 actionId) {
        bytes memory data = abi.encode(fileSlug);
        bytes32 actionHash = keccak256(abi.encodePacked('deleteFile', data));
        uint256 pendingActionId = pendingActionByHash[actionHash];
        require(
            pendingActionId == 0,
            string(abi.encodePacked("Action already pending: ", pendingActionId.toString()))
        );
        actionId = _createAction(actionHash, ActionType.DeleteFile, data);
        _acceptAction(actionId);
    }

    // Safetynet setup by file slug and recipient email
    function safetyNetByEmail(bytes32 fileSlug, bytes32 emailHash)
    external
    onlyParticipant returns (uint256 actionId)
    {
        bytes memory data = abi.encode(fileSlug, emailHash);
        bytes32 actionHash = keccak256(abi.encodePacked('safetyNetByEmail', data));
        uint256 pendingActionId = pendingActionByHash[actionHash];
        require(
            pendingActionId == 0,
            string(abi.encodePacked("Action already pending: ", pendingActionId.toString()))
        );

        actionId = _createAction(actionHash, ActionType.SafetyNetByEmail, data);
        _acceptAction(actionId);
    }

    // Safetynet setup by file slug and recipient wallet address
    function safetyNetByWallet(bytes32 fileSlug, address recipientAddress)
    external
    onlyParticipant returns (uint256 actionId)
    {
        bytes memory data = abi.encode(fileSlug, recipientAddress);
        bytes32 actionHash = keccak256(abi.encodePacked('safetyNetByAddress', data));
        uint256 pendingActionId = pendingActionByHash[actionHash];
        require(
            pendingActionId == 0,
            string(abi.encodePacked("Action already pending: ", pendingActionId.toString()))
        );
        actionId = _createAction(actionHash, ActionType.SafetyNetByWallet, data);
        _acceptAction(actionId);
    }

    function acceptAction(uint256 actionId) external onlyParticipant {
        require(
            _actions[actionId].exists,
            "WorkspaceMultiSigUpgradeable: action does not exist"
        );
        require(
            _actions[actionId].participantStatuses[msg.sender] != ParticipantStatus.ACCEPTED,
            "WorkspaceMultiSigUpgradeable: action already accepted by current participant"
        );
        require(
            _actions[actionId].actionStatus == ActionStatus.PENDING,
            "WorkspaceMultiSigUpgradeable: action already done"
        );

        _acceptAction(actionId);
    }

    function _acceptAction(uint256 actionId) private {
        _actions[actionId].participantStatuses[_msgSender()] = ParticipantStatus.ACCEPTED;
        _actions[actionId].acceptedCount += 1;
        _actions[actionId].pendingCount -= 1;

        _updateActionStatus(actionId);
    }

    // Function to decline an action
    function declineAction(uint256 actionId) external onlyParticipant {
        Action storage action = _actions[actionId];
        require(
            action.exists,
            "WorkspaceMultiSigUpgradeable: action does not exist"
        );
        require(
            action.participantStatuses[_msgSender()] != ParticipantStatus.DECLINED,
            "WorkspaceMultiSigUpgradeable: action already declined current participant"
        );

        // if nobody except of creator vote yet and creator declining, decline whole action
        if (
            action.acceptedCount == 1
            && action.creator == _msgSender()
        ) {
            action.actionStatus = ActionStatus.DECLINED;
        }

        action.participantStatuses[_msgSender()] = ParticipantStatus.DECLINED;
        action.declinedCount += 1;
        action.pendingCount -= 1;

        _updateActionStatus(actionId);
    }

    // Function to get the status and type of an action by its ID
    function getActionInfo(uint256 actionId)
    public
    view
    returns (ActionType actionType, ActionStatus actionStatus, bytes32 actionHash)
    {
        require(
            _actions[actionId].exists,
            "WorkspaceMultiSigUpgradeable: action does not exist"
        );
        actionType = _actions[actionId].actionType;
        actionStatus = _actions[actionId].actionStatus;
        actionHash = _actions[actionId].actionHash;
    }

    // Function to get the status of a participant within an action
    function getParticipantStatusInAction(uint256 actionId, address participant)
    public
    view
    returns (ParticipantStatus)
    {
        require(
            _actions[actionId].exists,
            "WorkspaceMultiSigUpgradeable: action does not exist"
        );
        return _actions[actionId].participantStatuses[participant];
    }

    function hasAccessByWallet(bytes32 fileSlug, address wallet) public view returns (bool) {
        return fileAccessByWallet[fileSlug][wallet];
    }

    function hasAccessByEmail(bytes32 fileSlug, bytes32 emailHash) public view returns (bool) {
        return fileAccessByEmail[fileSlug][emailHash];
    }

    function isParticipant(address _address) public view returns (bool) {
        return _signingSchema.participants[_address].exists;
    }

    function participantsRequired() public view returns (uint8) {
        return _signingSchema.requiredParticipants;
    }

    // Internal function to update the overall action status based on the participant statuses
    function _updateActionStatus(uint256 actionId) internal {
        Action storage action = _actions[actionId];

        if (action.acceptedCount >= participantsRequired()) {
            action.actionStatus = ActionStatus.ACCEPTED;
            action.acceptedAt = block.timestamp;

            if (action.actionType == ActionType.AddParticipant) {
                _addParticipant(abi.decode(action.data, (address)));
            } else if (action.actionType == ActionType.ChangeParticipantsRequired) {
                _changeRequiredParticipants(abi.decode(action.data, (uint8)));
            } else if (action.actionType == ActionType.RemoveParticipant) {
                _removeParticipant(abi.decode(action.data, (address)));
            } else if (action.actionType == ActionType.ShareFileByWallet) {
                (bytes32 fileSlug, address recipient) = abi.decode(action.data, (bytes32, address));
                fileAccessByWallet[fileSlug][recipient] = true;
            } else if (action.actionType == ActionType.ShareFileByEmail) {
                (bytes32 fileSlug, bytes32 emailHash) = abi.decode(action.data, (bytes32, bytes32));
                fileAccessByEmail[fileSlug][emailHash] = true;
            } else if (action.actionType == ActionType.DeleteFile) {
                (bytes32 fileSlug) = abi.decode(action.data, (bytes32));
                fileIsDeleted[fileSlug] = true;
            }

            pendingActionByHash[action.actionHash] = 0;

        } else if (action.declinedCount >= participantsRequired()) {
            action.actionStatus = ActionStatus.DECLINED;
            action.declinedAt = block.timestamp;
            pendingActionByHash[action.actionHash] = 0;
        }

        emit ActionUpdated(
            actionId, action.actionHash, action.actionStatus,
            action.acceptedCount, action.declinedCount, action.pendingCount
        );

    }


    function _createAction(bytes32 actionHash, ActionType actionType, bytes memory data) internal returns (uint256) {
        uint256 actionId = nextActionId++;
        address[] memory participants = currentParticipants();

        _actions[actionId].actionId = actionId;
        _actions[actionId].actionHash = actionHash;
        _actions[actionId].actionType = actionType;
        _actions[actionId].pendingCount = uint8(participants.length);
        _actions[actionId].actionStatus = ActionStatus.PENDING;
        _actions[actionId].createdAt = block.timestamp;
        _actions[actionId].creator = _msgSender();
        _actions[actionId].exists = true;
        _actions[actionId].data = data;

        pendingActionByHash[actionHash] = actionId;

        emit ActionUpdated(
            actionId, _actions[actionId].actionHash, ActionStatus.PENDING,
            _actions[actionId].acceptedCount, _actions[actionId].declinedCount, _actions[actionId].pendingCount
        );

        return actionId;
    }

    modifier onlyParticipant() {
        require(
            _signingSchema.participants[_msgSender()].exists,
            "WorkspaceMultiSigUpgradeable: caller is not a participant"
        );
        _;
    }

    modifier onlyPendingParticipant(uint256 actionId) {
        require(
            _signingSchema.participants[_msgSender()].exists
            && _actions[actionId].participantStatuses[_msgSender()] == ParticipantStatus.PENDING,
            "WorkspaceMultisigUpgradeable: Only multisig participant, only pending action"
        );
        _;
    }
}