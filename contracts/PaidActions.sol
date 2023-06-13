// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.9;

abstract contract PaidActions {

    function getFeeCollector() public virtual view returns(address);

    function _payFee(uint256 amount) internal {
        _withdraw(getFeeCollector(), amount);
    }

    function _withdraw(address to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        require(success, "PaidActions: fee transfer failed");
    }

}