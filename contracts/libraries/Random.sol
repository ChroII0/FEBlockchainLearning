// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

library Random {
    function randomNumber(uint256 length,uint256 valueRandomClientSide, uint256 secretValueRandom) internal view returns (uint256) {
        uint256 seed = uint256(keccak256(abi.encodePacked(
                                                        block.timestamp,
                                                        blockhash(block.number - 1),
                                                        block.difficulty,
                                                        valueRandomClientSide,
                                                        secretValueRandom)));
        uint256 random = seed % length;
        return random;
    }
}