// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.9;

interface IRegistry {
    function getERC2981ReceiverAddress() external view returns (address);
    function getLiquidityRecipient() external view returns (address);
    function getDonationRecipient() external view returns (address);
    function getProfitRecipient() external view returns (address);
    function getGhostMinterContract() external view returns (address);
    function getReferalRewardsContract() external view returns (address);
    function getDistributionManagerContract() external view returns (address);
    function getListHelper() external view returns (address);
    function getShopSigned() external view returns (address);
    function getContract(bytes32 name) external view returns (address);
    function hasContract(bytes32 name) external view returns (bool);
    function getUpgrader() external view returns (address);
    function getImplementation(bytes32 name) external returns (address);
    function injectDependencies(bytes32 name) external;
    function upgradeContract(bytes32 name, address newImplementation) external;
    function upgradeContractAndCall(bytes32 name, address newImplementation, string calldata functionSignature) external;
    function addContract(bytes32 name, address contractAddress) external;
    function addProxyContract(bytes32 name, address implAddress) external;
    function addNft(bytes32 name) external;
    function removeNft(bytes32 name) external;
    function addShop(bytes32 name) external;
    function removeShop(bytes32 name) external;
    function addNftContract(bytes32 name, address contractAddress) external;
}
