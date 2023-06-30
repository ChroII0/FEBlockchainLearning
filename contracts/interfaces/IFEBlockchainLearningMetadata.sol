// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "../libraries/Session.sol";

interface IFEBlockchainLearningMetadata {
    function sessionJoined() external view returns(uint256[] memory);
    function allMysession() external view returns(Session.Detail[] memory);
    function supplyFeToken(address owner) external view returns(uint256);
    function allSession() external view returns(Session.Info[] memory);
    function sessionById(uint256 sessionId) external view returns(Session.Info memory session);
    function getDataDoTraining(uint256 sessionId) external view returns(uint256, uint256);
    function getDataDoChecking(uint256 sessionId) external view returns(uint256[] memory);
    function selectCandidateAggregator(uint256 sessionId) external view returns(uint256 candidatesEncode);
    function checkOpportunityAggregate(uint256 sessionId) external view returns(bool);
    function getDataDoAggregate(uint256 sessionId) external view returns(uint256[] memory);
    function getDataDoTesting(uint256 sessionId) external view returns(uint256, uint256[] memory);

    function getMetadataForPerformanceRewardDistribution(
        address trainer, 
        uint256 sessionId, 
        uint256 round) external view returns(address[] memory trainers, Session.TrainerDetail[] memory trainerDetails);
}