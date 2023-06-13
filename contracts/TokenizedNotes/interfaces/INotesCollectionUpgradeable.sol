// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";

interface INotesCollectionUpgradeable  is IERC1155Upgradeable {

    function initialize(address creator, string memory name_, uint256 workspaceId_) external;

    function uri(uint256) external view returns (string memory);

    function mint(address to, uint256 id, uint256 amount, bytes memory data) external;

    function mintMultiple(address[] memory to, uint256 id, uint256[] memory amounts, bytes memory data) external;

    function addToken(string memory fileId) external;
}