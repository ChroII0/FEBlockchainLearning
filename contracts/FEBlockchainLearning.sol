// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/IFEBlockchainLearning.sol";
import "./interfaces/ITrainerManagement.sol";
import "./interfaces/IAdminControl.sol";
import "./interfaces/IFEToken.sol";
import "./libraries/Session.sol";
import "./libraries/Random.sol";


contract FEBlockchainLearning is IFEBlockchainLearning {
    using Random for uint256[];

    Session.Detail[] private _sessions;
    mapping (uint256 => uint256) public BalanceFeTokenInSession;
    mapping (uint256 => uint256) private _keyOfSessionDetailBySessionId;
    mapping (uint256 => mapping(address => Session.TrainerStatus)) private statusTrainers; 
    mapping (uint256 => mapping(address => Session.scoreObject)) private scoreObjects;
    mapping (uint256 => mapping(address => uint256)) private trainUpdates;
    mapping (address => Session.TesterStatus) private testers;

    
    uint256 public MIN_ROUND = 1;
    uint256 public MAX_ROUND = 10;
    uint256 public MIN_TRAINER_IN_ROUND = 5;
    uint256 public MAX_TRAINER_IN_ROUND = 100;
    uint256 public immutable MIN_REWARD = MIN_ROUND * MIN_TRAINER_IN_ROUND;

    uint256 public constant REWARD_DECIMAL = 10**4;
    uint256 public BASE_TRAINING_REWARD_RATE = 500; // 5%
    uint256 public BASE_TESTING_REWARD_RATE = 500; // 5%
    uint256 public BASE_AGGREGATE_REWARD_RATE = 1000; // 10%
    uint256 public immutable PERFORMANCE_REWARD_RATE = REWARD_DECIMAL - BASE_TRAINING_REWARD_RATE + BASE_TESTING_REWARD_RATE + BASE_AGGREGATE_REWARD_RATE;

    ITrainerManagement private _trainerManagement;
    IAdminControl private _adminControl;
    IFEToken private _feToken;

    constructor(address adminControl, address trainerManagementAddress, address feToken) {
        _trainerManagement = ITrainerManagement(trainerManagementAddress);
        _adminControl = IAdminControl(adminControl);
        _feToken = IFEToken(feToken);
    }

    modifier onlyAdmin(address account) {
        require(_adminControl.isAdmin(account) == true, "You are not admin");
        _;
    }
    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "Lock");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // event SetBaseRewardRate(uint256 baseTrainingRewardRate, uint256 baseTestingRewardRate, uint256 baseAggregateRate);
    event SessionCreated(address indexed owner, uint256 indexed sessionId, uint256 reward);
    event SessionRemoved(address indexed owner, uint256 indexed sessionId, uint256 rewardRemaining);

    function setRound(uint256 newMinRound, uint256 newMaxRound) external override onlyAdmin(msg.sender) {
        require(newMaxRound > newMinRound &&  newMinRound> 0);
        MIN_ROUND = newMinRound;
        MAX_ROUND = newMaxRound;
    }
    function setNumTrainerInRound(uint256 newMinTrainerInRound, uint256 newMaxTrainerInRound) external override onlyAdmin(msg.sender) {
        require(newMaxTrainerInRound > newMinTrainerInRound && newMinTrainerInRound > 0);
        MIN_TRAINER_IN_ROUND = newMinTrainerInRound;
        MAX_TRAINER_IN_ROUND = newMaxTrainerInRound;
    }
    function setBaseRewardRate(
        uint256 baseTrainingRewardRate,
        uint256 baseTestingRewardRate,
        uint256 baseAggregateRate
        ) external override onlyAdmin(msg.sender){
        require(baseTrainingRewardRate > 0);
        require(baseTestingRewardRate > 0);
        require(baseAggregateRate > 0);
        require(baseTrainingRewardRate + baseTestingRewardRate + baseAggregateRate < REWARD_DECIMAL);
        BASE_TRAINING_REWARD_RATE = baseTrainingRewardRate;
        BASE_TESTING_REWARD_RATE = baseTestingRewardRate;
        BASE_AGGREGATE_REWARD_RATE = baseAggregateRate;
    }
    function allSession() external view override returns(Session.Info[] memory){
        Session.Info[] memory sessionInfo = new Session.Info[](_sessions.length);
        for (uint256 i = 0; i < _sessions.length; i++){
            sessionInfo[i] = _sessions[i].info;
        }
        return sessionInfo;
    }
    function sessionById(uint256 sessionId) external view returns(Session.Info memory) {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        return _sessions[key].info;
    }

    function getOtherTrainerDoTest(uint256 sessionId) external view override returns(address, uint256){
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        require(testers[msg.sender].isTester == false);
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Scoring);
        require(statusTrainers[sessionId][msg.sender] == Session.TrainerStatus.Trained);
        uint256 len = _sessions[key].numberTrainerNotYetSelectedForTesting;
        uint256[] memory notYetSelectedForTesting = new uint256[](len);
        uint256 cnt = 0;
        for (uint256 i = 0; i < _sessions[key].trainers.length; i++){
            address currectTrainer = _sessions[key].trainers[i];
            Session.TrainerStatus trainerStatus = statusTrainers[sessionId][currectTrainer];
            if (trainerStatus == Session.TrainerStatus.Trained && currectTrainer != msg.sender)
            {  
                notYetSelectedForTesting[cnt] = i;
                cnt++;
            }
        }
        uint256 randomKey = Random.randomArrayValue(notYetSelectedForTesting);
        address otherTrainer = _sessions[key].trainers[randomKey];
        return (otherTrainer, trainUpdates[sessionId][otherTrainer]);
    }
    function applyTesting(uint256 sessionId, address trainerSelected) external override {
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Scoring);
        require(statusTrainers[sessionId][msg.sender] == Session.TrainerStatus.Trained);
        require(statusTrainers[sessionId][trainerSelected] == Session.TrainerStatus.Trained);
        statusTrainers[sessionId][trainerSelected] = Session.TrainerStatus.Testing;
        _sessions[key].numberTrainerNotYetSelectedForTesting -= 1;
        testers[msg.sender].isTester = true;
        testers[msg.sender].trainerSelected = trainerSelected;
    }
    function checkOpportunityAggregate(uint256 sessionId) external view override returns(bool){
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        return _sessions[key].aggreator == msg.sender;
    }







    function createSession(
        uint256 sessionId,
        uint256 maxRound,
        uint256 maxTrainerInOneRound,
        uint256 globalModelId,
        uint256 latestGlobalModelParamId
    ) external payable lock override {
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        require(MIN_ROUND <= maxRound && maxRound <=  MAX_ROUND);
        require(MIN_TRAINER_IN_ROUND <= maxTrainerInOneRound && maxTrainerInOneRound <= MAX_TRAINER_IN_ROUND);
        require(msg.value >= MIN_REWARD);
        Session.Detail memory sDetail;
        sDetail.info.sessionId = sessionId;
        sDetail.info.owner = msg.sender;
        sDetail.info.status = Session.RoundStatus.Training;
        sDetail.info.performanceReward = msg.value * PERFORMANCE_REWARD_RATE;
        sDetail.info.baseReward.trainingReward = msg.value * BASE_TRAINING_REWARD_RATE / maxRound / maxTrainerInOneRound;
        sDetail.info.baseReward.testingReward = msg.value * BASE_TESTING_REWARD_RATE / maxRound / maxTrainerInOneRound;
        sDetail.info.baseReward.aggregateReward = msg.value * BASE_AGGREGATE_REWARD_RATE / maxRound;
        sDetail.info.maxRound = maxRound;
        sDetail.info.maxTrainerInOneRound = maxTrainerInOneRound;
        sDetail.globalModelId = globalModelId;
        sDetail.latestGlobalModelParamId = latestGlobalModelParamId;

        _sessions.push(sDetail);
        _keyOfSessionDetailBySessionId[sessionId] = _sessions.length - 1;
        uint256 totalReward = msg.value * REWARD_DECIMAL;
        BalanceFeTokenInSession[sessionId] = totalReward;

        emit SessionCreated(msg.sender, sessionId, totalReward);
    }
    function removeSession(uint256 sessionId) external lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.owner == msg.sender);
        uint256 rewardRemaining = BalanceFeTokenInSession[sessionId] / REWARD_DECIMAL;
        BalanceFeTokenInSession[sessionId] = 0;
        _sessions[key].info.currentRound = _sessions[key].info.maxRound;
        _sessions[key].info.status = Session.RoundStatus.End;
        payable(msg.sender).transfer(rewardRemaining);

        emit SessionRemoved(msg.sender, sessionId, rewardRemaining);
    }
    function applySession(uint256 sessionId) external override returns(uint256, uint256) {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Training);
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        _sessions[key].trainers.push(msg.sender);
        statusTrainers[sessionId][msg.sender] = Session.TrainerStatus.Training;
        return (_sessions[key].globalModelId, _sessions[key].latestGlobalModelParamId);
    }
    function _receiveTrainingReward(address trainer, uint256 sessionKey) internal {
        uint256 sessionId = _sessions[sessionKey].info.sessionId;
        uint256 reward = _sessions[sessionKey].info.baseReward.trainingReward;
        _feToken.mint(trainer, reward);
        BalanceFeTokenInSession[sessionId] -= reward;
    }
    function submitUpdate(uint256 sessionId, uint256 updateId) external override lock {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Training);
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        require(statusTrainers[sessionId][msg.sender] == Session.TrainerStatus.Training);
        trainUpdates[sessionId][msg.sender] = updateId;
        statusTrainers[sessionId][msg.sender] == Session.TrainerStatus.Trained;
        _sessions[key].numberOfTrainingSubmitted += 1;
        _sessions[key].numberTrainerNotYetSelectedForTesting += 1;
        _feToken.mint(msg.sender, _sessions[key].info.baseReward.trainingReward);

        _receiveTrainingReward(msg.sender, key);
        if (_sessions[key].numberOfTrainingSubmitted == _sessions[key].trainers.length)
        {
            _sessions[key].info.status = Session.RoundStatus.Scoring;
        }
    }
    function _receiveTestingReward(address trainer, uint256 sessionKey) internal {
        uint256 sessionId = _sessions[sessionKey].info.sessionId;
        uint256 reward = _sessions[sessionKey].info.baseReward.testingReward;
        _feToken.mint(trainer, reward);
        BalanceFeTokenInSession[sessionId] -= reward;
    }
    function submitScores(uint256 sessionId, uint256[] memory scores, address trainerSelected) external override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Scoring);
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        require(scores.length == 5);
        require(testers[msg.sender].isTester == true);
        require(testers[msg.sender].trainerSelected == trainerSelected);
        statusTrainers[sessionId][trainerSelected] = Session.TrainerStatus.Tested;
        _sessions[key].numberOfTestingSubmitted += 1;
        Session.scoreObject memory _scoreObj = Session.scoreObject(
            scores[0],
            scores[1],
            scores[2],
            scores[3],
            scores[4]
        );
        scoreObjects[sessionId][trainerSelected] = _scoreObj;

        _receiveTestingReward(msg.sender, key);
        if (_sessions[key].numberOfTestingSubmitted == _sessions[key].trainers.length)
        {
            _sessions[key].info.status = Session.RoundStatus.Scored;
        }
    }
    function submitAggregate(uint256 sessionId, uint256 updateId) external override {}
    function claimReward(uint256 sessionId) external lock override {}
}