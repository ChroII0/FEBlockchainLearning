// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IPerformanceRewardDistributionMetadata {
    function getCompletedRound(address trainer, uint256 sessionId)
        external view returns(uint256[] memory rounds, bool[] memory isClaimeds);
}