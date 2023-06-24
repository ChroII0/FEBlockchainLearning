// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IAdminControlMetadata {
    function isAdmin(address account) external view returns (bool);
    function isMinter(address account) external view returns (bool);
    function isBurner(address account) external view returns (bool);
    function isCallerTimeLock(address account) external view returns(bool);
}