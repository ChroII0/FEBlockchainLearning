// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./interfaces/IAdminControl.sol";

contract FEToken is ERC20, ERC20Burnable {

    IAdminControl private _adminControl;

    mapping (address => bool) alreadyTrainers;
    constructor(address adminControl) ERC20("FE Token", "FET") {
        _adminControl = IAdminControl(adminControl);
    }
    modifier onlyMinter(address account) {
        require(_adminControl.isMinter(account) == true, "You are not minter");
        _;
    }
    modifier onlyBurner(address account) {
        require(_adminControl.isBurner(account) == true, "You are not burner");
        _;
    }
    function mint(address to, uint256 amount) external onlyMinter(msg.sender){
        _mint(to, amount);
    }
    function burn(address to, uint256 amount) external onlyBurner(msg.sender){
        _burn(to, amount);
    }

}
