// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";

interface IFileAccessCollectionUpgradeable is IERC1155Upgradeable {

    struct SMintMultipleCall {
        uint256 id;
        address[] to;
        uint256[] amounts;
        uint256 callCost;
        bytes32 interactionId;
        address from;
    }

    struct SAddTokenCall {
        string slug;
        uint96 royalties;
        uint256 tokenMaxSupply;
        uint256 callCost;
        bytes32 interactionId;
        address from;
    }

    struct SMaxSupplyCall {
        uint256 tokenId;
        uint256 tokenMaxSupply;
        bytes32 interactionId;
        address from;
    }

    function maxSupply(uint256 id) external view returns (uint256);
    function initialize(address creator, string memory name_, string memory description_) external;
    function uri(uint256) external view returns (string memory);
    function mintMultiple(SMintMultipleCall calldata req, bytes memory signature) external payable;
    function setTokenRoyaltyPercentage(uint256 tokenId, uint96 _royaltyPercentage) external;
}