// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/IAdminControlMetadata.sol";
import "./interfaces/IFEToken.sol";

contract FEToken is IFEToken{

    IAdminControlMetadata private _adminControl;
    mapping(address => uint256) private _balances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    constructor(address adminControl, string memory name_, string memory symbol_) {
        _adminControl = IAdminControlMetadata(adminControl);
        _name = name_;
        _symbol = symbol_;
    }
    modifier onlyMinter(address account) {
        require(_adminControl.isMinter(account) == true, "You are not minter");
        _;
    }
    modifier onlyBurner(address account) {
        require(_adminControl.isBurner(account) == true, "You are not burner");
        _;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }


   
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "FET: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "FET: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "FET: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

   
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal {}

    function _afterTokenTransfer(address from, address to, uint256 amount) internal {}


    function mint(address to, uint256 amount) external onlyMinter(msg.sender){
        _mint(to, amount);
    }
    function burn(address to, uint256 amount) external onlyBurner(msg.sender){
        _burn(to, amount);
    }

}
