// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IFETokenMetadata {

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}