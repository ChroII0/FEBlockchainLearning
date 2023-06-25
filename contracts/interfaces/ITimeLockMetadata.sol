// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ITimeLockMetadata {
    function getExpirationTimeOfEachRoundInSession(uint256 sessionId) external view returns(uint256,uint256,uint256,uint256);
    function getStartTimeOfEachRoundInSession(uint256 sessionId) external view returns(uint256,uint256,uint256,uint256);
    function getExpirationTimeOfSelectCandidateAggregatorAndApply() external pure returns(uint256,uint256);
    function checkExpirationTimeOfTrainingRound(uint256 sessionId) external view returns(bool);
    function checkExpirationTimeOfCheckingRound(uint256 sessionId) external view returns(bool);
    function checkExpirationTimeOfAggregatingRound(uint256 sessionId) external view returns(bool);
    function checkExpirationTimeOfTestRound(uint256 sessionId) external view returns(bool);
}