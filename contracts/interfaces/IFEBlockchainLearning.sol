// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IFEBlockchainLearningMetadata.sol";
interface IFEBlockchainLearning is IFEBlockchainLearingMetadata{
    function setRound(uint256 newMinRound, uint256 newMaxRound) external;
    function setNumTrainerInRound(uint256 newMinTrainerInRound, uint256 newMaxTrainerInRound) external;
    function setBaseRewardRate(uint256 baseTrainingRewardRate, uint256 baseTestingRewardRate, uint256 baseAggregateRate) external;
    function createSession(
        uint256 sessionId,
        uint256 maxRound,
        uint256 maxTrainerInOneRound,
        uint256 globalModelId,
        uint256 latestGlobalModelParamId
    ) external payable;
    function removeSession(uint256 sessionId) external;
    function applySession(uint256 sessionId) external returns(uint256, uint256);
    function applyTesting(uint256 sessionId, address trainerSelected) external;
    function submitUpdate(uint256 sessionId, uint256 updateId) external;
    function submitScores(uint256 sessionId, uint256[] memory scores, address trainerSelected) external;
    function submitAggregate(uint256 sessionId, uint256 updateId) external;
    function claimReward(uint256 sessionId) external;
}