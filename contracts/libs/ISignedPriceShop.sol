// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

interface ISignedPriceShop {

    struct SPaidMintCall {
        bytes32 tokenSlug;
        uint256 tokenId;
        address referrer;
        bytes32 referrerTokenSlug;
        uint256 referrerTokenId;
        uint256 price;
        bytes32 interactionId;
        address from;
    }

    function buy(
        SPaidMintCall calldata req,
        bytes memory signature
    ) external payable;

    function signWallet() external view returns (address);

    function domainSeparator() external view returns (bytes32);
}