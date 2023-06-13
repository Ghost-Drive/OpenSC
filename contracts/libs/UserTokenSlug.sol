// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

library UserTokenSlug {

    function toUserTokenSlug(address contractAddress) public pure returns(bytes32) {
        return bytes32(bytes20(contractAddress));
    }

    function fromUserTokenSlug(bytes32 slug) public pure returns(address) {
        require(
            isValidSlug(slug),
            "Token slug doesn't look like user's token"
        );

        return address(uint160(bytes20(slug)));
    }

    function isValidSlug(bytes32 slug) public pure returns (bool) {
        return bytes12(uint96(uint256(slug))) == bytes12(0x0);
    }

}