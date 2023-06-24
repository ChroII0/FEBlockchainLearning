// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

library Random {
    function randomNumber(uint256 length) internal view returns (uint256) {
        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1), block.difficulty)));
        uint256 random = seed % length;
        return random;
    }
    
    // function randomArrayValue(uint256[] memory arr) public view returns (uint256) {
        
    //     uint256 randomIndex = randomNumber(arr.length);
    //     uint256 randomValue = arr[randomIndex];
        
    //     return randomValue;
    // }
}