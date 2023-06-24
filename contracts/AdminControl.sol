// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IAdminControlMetadata.sol";

contract AdminControl is AccessControl, IAdminControlMetadata{

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant CALLER_TIME_LOCK = keccak256("CALLER_TIME_LOCK");
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function isAdmin(address account) external view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account);
    }
    function isMinter(address account) external view override returns(bool) {
        return hasRole(MINTER_ROLE, account);
    }
    function isBurner(address account) external view override returns(bool) {
        return hasRole(BURNER_ROLE, account);
    }
    function isCallerTimeLock(address account) external view override returns(bool) {
        return hasRole(CALLER_TIME_LOCK, account);
    }
    
    function setMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, minter);
    }
    function setBurner(address burner) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(BURNER_ROLE, burner);
    }
    function setCallerTimeLock(address caller) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(CALLER_TIME_LOCK, caller);
    }
}
