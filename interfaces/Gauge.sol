// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

interface Gauge {
    function deposit(uint) external;
    function balanceOf(address) external view returns (uint);
    function withdraw(uint) external;
}

interface Mintr {
    function mint(address) external;
}
