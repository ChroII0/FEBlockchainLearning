// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IFETokenMetadata.sol";

interface IFEToken is IFETokenMetadata{

    function mint(address to, uint256 amount) external;
    function burn(address to, uint256 amount) external;
}