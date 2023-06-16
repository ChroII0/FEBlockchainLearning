// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "../libraries/Session.sol";

interface IFEBlockchainLearingMetadata {
    function sessionJoined() external view returns(uint256[] memory);
    function balanceFeTokenInSession(uint256 sessionId) external view returns(uint256);
    function supplyFeToken(address owner) external view returns(uint256);
    function allSession() external view returns(Session.Info[] memory);
    function sessionById(uint256 sessionId) external view returns(Session.Info memory);
    function getOtherTrainerDoTest(uint256 sessionId) external view returns(address, uint256);
    function selectCandidateAggregator(uint256 sessionId) external view returns(address[] memory);
    function checkOpportunityAggregate(uint256 sessionId) external view returns(bool);
    function getDataDoAggregate(uint256 sessionId) external view returns(uint256[] memory);
}