// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

interface INotesActionCounter
{
    function addTokensMinted(address user, uint64 minted) external;

    function addTokensCreated(address user, uint64 created) external;
}