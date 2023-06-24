// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/ITimeLock.sol";
import "./interfaces/IAdminControlMetadata.sol";

contract TimeLock is ITimeLock{


    struct ExpirationTime {
        uint256 trainingRound;
        uint256 checkingRound;
        uint256 aggregatingRound;
        uint256 testingRound;
    }
    struct StartTime {
        uint256 trainingRound;
        uint256 checkingRound;
        uint256 aggregatingRound;
        uint256 testingRound;
    }
    struct TimeLockInfo {
        ExpirationTime expirationTime;
        StartTime startTime;
    }
    // uint256 public constant maxExpirationTimeOfReadyRound = 3 days;
    uint256 public minExpirationTimeOfTrainingRound = 3 days;
    uint256 public minExpirationTimeOfCheckingRound = 3 days;
    uint256 public minExpirationTimeOfAggregatingRound = 3 days;
    uint256 public minExpirationTimeOfTestingRound = 3 days;

    uint256 public maxExpirationTimeOfTrainingRound = 7 days;
    uint256 public maxExpirationTimeOfCheckingRound = 7 days;
    uint256 public maxExpirationTimeOfAggregatingRound = 7 days;
    uint256 public maxExpirationTimeOfTestingRound = 7 days;


    mapping (uint256 => TimeLockInfo) private _sessionsTimeLockInfo;

    IAdminControlMetadata private _adminControl;

    constructor(address adminControl) {
        _adminControl = IAdminControlMetadata(adminControl);
    }
    modifier onlyAdmin(address account) {
        require(_adminControl.isAdmin(account) == true, "You are not admin");
        _;
    }
    modifier onlyCaller(address account) {
        require(_adminControl.isCallerTimeLock(account) == true, "You are not allow caller");
        _;
    }

    function getExpirationTimeOfEachRoundInSession(uint256 sessionId) external view override returns(uint256,uint256,uint256,uint256) {
        return (
        _sessionsTimeLockInfo[sessionId].expirationTime.trainingRound,
        _sessionsTimeLockInfo[sessionId].expirationTime.checkingRound,
        _sessionsTimeLockInfo[sessionId].expirationTime.aggregatingRound,
        _sessionsTimeLockInfo[sessionId].expirationTime.testingRound
        );
    }
    function checkExpirationTimeOfTrainingRound(uint256 sessionId) external view override returns(bool) {
        return (
            block.timestamp - _sessionsTimeLockInfo[sessionId].startTime.trainingRound
            < _sessionsTimeLockInfo[sessionId].expirationTime.trainingRound
        );
    }
    function checkExpirationTimeOfCheckingRound(uint256 sessionId) external view override returns(bool) {
        return (
            block.timestamp - _sessionsTimeLockInfo[sessionId].startTime.checkingRound
            < _sessionsTimeLockInfo[sessionId].expirationTime.checkingRound
        );
    }
    function checkExpirationTimeOfAggregatingRound(uint256 sessionId) external view override returns(bool) {
        return (
            block.timestamp - _sessionsTimeLockInfo[sessionId].startTime.aggregatingRound
            < _sessionsTimeLockInfo[sessionId].expirationTime.aggregatingRound
        );
    }
    function checkExpirationTimeOfTestRound(uint256 sessionId) external view override returns(bool) {
        return (
            block.timestamp - _sessionsTimeLockInfo[sessionId].startTime.testingRound
            < _sessionsTimeLockInfo[sessionId].expirationTime.testingRound
        );
    }


    function setLimitExpirationTimeOfEachRoundInSession(
        uint256 newMinExpirationTimeOfTrainingRound,
        uint256 newMinExpirationTimeOfCheckingRound,
        uint256 newMinExpirationTimeOfAggregatingRound,
        uint256 newMinExpirationTimeOfTestingRound,
        uint256 newMaxExpirationTimeOfTrainingRound,
        uint256 newMaxExpirationTimeOfCheckingRound,
        uint256 newMaxExpirationTimeOfAggregatingRound,
        uint256 newMaxExpirationTimeOfTestingRound
        ) external onlyAdmin(msg.sender) override {
            minExpirationTimeOfTrainingRound = newMinExpirationTimeOfTrainingRound;
            minExpirationTimeOfCheckingRound = newMinExpirationTimeOfCheckingRound;
            minExpirationTimeOfAggregatingRound = newMinExpirationTimeOfAggregatingRound;
            minExpirationTimeOfTestingRound = newMinExpirationTimeOfTestingRound;
            maxExpirationTimeOfTrainingRound = newMaxExpirationTimeOfTrainingRound;
            maxExpirationTimeOfCheckingRound = newMaxExpirationTimeOfCheckingRound;
            maxExpirationTimeOfAggregatingRound = newMaxExpirationTimeOfAggregatingRound;
            maxExpirationTimeOfTestingRound = newMaxExpirationTimeOfTestingRound;
    }
    function setExpirationTimeOfEachRoundInSession(
        uint256 sessionId,
        uint256 expirationTimeOfTrainingRound,
        uint256 expirationTimeOfCheckingRound,
        uint256 expirationTimeOfAggregatingRound,
        uint256 expirationTimeOfTestingRound
        ) external onlyCaller(msg.sender) override {
        require(
            minExpirationTimeOfTrainingRound <= expirationTimeOfTrainingRound
            && expirationTimeOfTrainingRound <= maxExpirationTimeOfTrainingRound);
        require(
            minExpirationTimeOfCheckingRound <= expirationTimeOfCheckingRound
            && expirationTimeOfCheckingRound <= maxExpirationTimeOfCheckingRound);
        require(
            minExpirationTimeOfAggregatingRound <= expirationTimeOfAggregatingRound
            && expirationTimeOfAggregatingRound <= maxExpirationTimeOfAggregatingRound);
        require(
            minExpirationTimeOfTestingRound <= expirationTimeOfAggregatingRound
            && expirationTimeOfAggregatingRound <=  maxExpirationTimeOfTestingRound);

        _sessionsTimeLockInfo[sessionId].expirationTime.trainingRound = expirationTimeOfTrainingRound;
        _sessionsTimeLockInfo[sessionId].expirationTime.checkingRound = expirationTimeOfCheckingRound;
        _sessionsTimeLockInfo[sessionId].expirationTime.aggregatingRound = expirationTimeOfAggregatingRound;
        _sessionsTimeLockInfo[sessionId].expirationTime.testingRound = expirationTimeOfTestingRound;
    }
    function setTrainingRoundStartTime(uint256 sessionId) external onlyCaller(msg.sender) override {
        _sessionsTimeLockInfo[sessionId].startTime.trainingRound = block.timestamp;
    }
    function setCheckingRoundStartTime(uint256 sessionId) external onlyCaller(msg.sender) override {
        _sessionsTimeLockInfo[sessionId].startTime.checkingRound = block.timestamp;
    }
    function setAggregatingRoundStartTime(uint256 sessionId) external onlyCaller(msg.sender) override {
        _sessionsTimeLockInfo[sessionId].startTime.aggregatingRound = block.timestamp;
    }
    function setTestingRoundStartTime(uint256 sessionId) external onlyCaller(msg.sender) override {
        _sessionsTimeLockInfo[sessionId].startTime.testingRound = block.timestamp;
    }
}