// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

interface IWorkspaceAccessUpgradeable {

    function initialize(address beneficiary_, uint256 accessCost_, uint256 workspaceId_) external;

}