// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IPerformanceRewardDistributionMetadata.sol";

interface IPerformanceRewardDistribution is IPerformanceRewardDistributionMetadata {
    function completeRoundOfSession(address trainer, uint256 sessionId, uint256 currentRound) external;
    function claim(address trainer, uint256 sessionId) external;
}