// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault is IERC20 {
    function token() external view returns (address);
    function claimInsurance() external; // NOTE: Only yDelegatedVault implements this
    function getPricePerFullShare() external view returns (uint);
    function deposit(uint) external;
    function withdraw(uint) external;
}
