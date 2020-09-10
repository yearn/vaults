// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

interface IController {
    function vaults(address) external view returns (address);
    function rewards() external view returns (address);
    function want(address) external view returns (address); // NOTE: Only StrategyControllerV2 implements this
    function balanceOf(address) external view returns (uint);
    function withdraw(address, uint) external;
    function earn(address, uint) external;
}
