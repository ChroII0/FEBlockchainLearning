// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ITimeLockMetadata.sol";

interface ITimeLock is ITimeLockMetadata {
    function setLimitExpirationTimeOfEachRoundInSession(
        uint256 newMinExpirationTimeOfTrainingRound,
        uint256 newMinExpirationTimeOfCheckingRound,
        uint256 newMinExpirationTimeOfAggregatingRound,
        uint256 newMinExpirationTimeOfTestingRound,
        uint256 maxExpirationTimeOfTrainingRound,
        uint256 maxExpirationTimeOfCheckingRound,
        uint256 maxExpirationTimeOfAggregatingRound,
        uint256 maxExpirationTimeOfTestingRound
        ) external;
    function setExpirationTimeOfEachRoundInSession(
        uint256 sessionId,
        uint256 expirationTimeOfTrainingRound,
        uint256 expirationTimeOfCheckingRound,
        uint256 expirationTimeOfAggregatingRound,
        uint256 expirationTimeOfTestingRound
        ) external;
    function setTrainingRoundStartTime(uint256 sessionId) external;
    function setCheckingRoundStartTime(uint256 sessionId) external;
    function setAggregatingRoundStartTime(uint256 sessionId) external;
    function setTestingRoundStartTime(uint256 sessionId) external;

}