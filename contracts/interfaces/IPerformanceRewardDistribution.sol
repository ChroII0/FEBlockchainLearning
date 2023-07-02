// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IPerformanceRewardDistributionMetadata.sol";

interface IPerformanceRewardDistribution is IPerformanceRewardDistributionMetadata {
    function setK(uint256 kx, uint256 ky) external;
    function completeRoundOfSession(address trainer, uint256 sessionId, uint256 currentRound) external;
    function claim(address trainer, uint256 sessionId, uint256 round, uint256 score, uint256 performanceRound, uint256 maxTrainer) external returns(uint256);
}