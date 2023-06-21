// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IFEToken {

    event Transfer(address indexed from, address indexed to, uint256 value);

    function mint(address to, uint256 amount) external;
    function burn(address to, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
}