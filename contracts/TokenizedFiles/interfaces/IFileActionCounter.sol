// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

interface IFileActionCounter
{
    function addTokensMinted(address user, uint256 minted) external;

    function addTokensCreated(address user, uint256 created) external;
}