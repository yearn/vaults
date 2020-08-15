// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

interface Vault {
    function token() external view returns (address);
    function claimInsurance() external;
    function getPricePerFullShare() external view returns (uint);
    function deposit(uint) external;
    function withdraw(uint) external;
}
