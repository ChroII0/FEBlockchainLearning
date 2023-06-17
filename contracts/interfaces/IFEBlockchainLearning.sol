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
    
    function applySession(uint256 sessionId) external;
    function applyTesting(uint256 sessionId) external;
    function applyAggregator(uint256 sessionId) external;
    
    function submitUpdate(uint256 sessionId, uint256 updateId) external;
    function submitScores(uint256 sessionId, uint256[] memory scores) external;

    function submitCandidateAggregator(uint256 sessionId, address[] memory candidates) external;
    function submitAggregate(uint256 sessionId, uint256 updateId, uint256[] memory indexOfTrainerHasBadUpdateId) external;
    
    function withdraw(uint256 amount) external;
}