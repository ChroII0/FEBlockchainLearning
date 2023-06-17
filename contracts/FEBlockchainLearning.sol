// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/IFEBlockchainLearning.sol";
import "./interfaces/ITrainerManagement.sol";
import "./interfaces/IAdminControl.sol";
import "./interfaces/IFEToken.sol";
import "./libraries/Session.sol";
import "./libraries/Random.sol";


contract FEBlockchainLearning is IFEBlockchainLearning {
    using Random for *;

    Session.Detail[] private _sessions;
    mapping (uint256 => uint256) private _randomTestingFactor;
    mapping (address => uint256[]) private _sessionKeysByOwner;
    
    mapping (uint256 => uint256) public balanceFeTokenInSession;
    mapping (address => uint256[]) private _sessionJoined;
    mapping (address => uint256) private _numCurrentSessionJoined;
    mapping (uint256 => uint256) private _keyOfSessionDetailBySessionId;
    mapping (uint256 => mapping (uint256 => address[])) private _trainers; // sessionId => round => trainer[]
    // sessionId => round => trainer 
    mapping (uint256 => mapping (uint256 => mapping (address => Session.TrainerDetail))) private _trainerDetails;
    mapping (uint256 => mapping (uint256 => address[])) private _candidateAggregator;

    // uint256 public constant LOCK_TIME_REWARD = 7 days;
    uint256 public constant MAX_SESSION_APPLY_SAME_TIME = 3;
    uint256 public constant MUN_CANDIDATE_AGGREGATOR = 5;
    uint256 public MIN_ROUND = 1;
    uint256 public MAX_ROUND = 10;
    uint256 public MIN_TRAINER_IN_ROUND = 5;
    uint256 public MAX_TRAINER_IN_ROUND = 100;
    uint256 public immutable MIN_REWARD = MIN_ROUND * MIN_TRAINER_IN_ROUND;
    uint256 public immutable ERROR_VOTE_REPORTED = (MIN_TRAINER_IN_ROUND - 1)/2 + (MIN_TRAINER_IN_ROUND - 1)%2;

    uint256 public constant REWARD_DECIMAL = 4;
    uint256 public constant SCORES_DECIMAL = 5;
    uint256 public BASE_TRAINING_REWARD_RATE = 500; // 5%
    uint256 public BASE_TESTING_REWARD_RATE = 1000; // 10%
    uint256 public BASE_AGGREGATE_REWARD_RATE = 500; // 5%
    uint256 public immutable PERFORMANCE_REWARD_RATE = 10**REWARD_DECIMAL - BASE_TRAINING_REWARD_RATE + BASE_TESTING_REWARD_RATE + BASE_AGGREGATE_REWARD_RATE;

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
        require(baseTrainingRewardRate + baseTestingRewardRate + baseAggregateRate < 10**REWARD_DECIMAL);
        BASE_TRAINING_REWARD_RATE = baseTrainingRewardRate;
        BASE_TESTING_REWARD_RATE = baseTestingRewardRate;
        BASE_AGGREGATE_REWARD_RATE = baseAggregateRate;
    }








    function sessionJoined() external view override returns(uint256[] memory) {
        return _sessionJoined[msg.sender];
    }
    function supplyFeToken(address owner) external view override returns(uint256) {
        return _feToken.balanceOf(owner);
    }
    function allSession() external view override returns(Session.Info[] memory){
        Session.Info[] memory sessionInfo = new Session.Info[](_sessions.length);
        for (uint256 i = 0; i < _sessions.length; i++){
            sessionInfo[i] = _sessions[i].info;
        }
        return sessionInfo;
    }
    function sessionById(uint256 sessionId) external view returns(Session.Info memory session) {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        session = _sessions[key].info;
    }
    function allMysession() external view override returns(Session.Detail[] memory) {
        uint256 len = _sessionKeysByOwner[msg.sender].length;
        Session.Detail[] memory sDetails = new Session.Detail[](len);
        for (uint256 i = 0; i < len; i++){
            sDetails[i] = _sessions[_sessionKeysByOwner[msg.sender][i]];
        }
        return sDetails;
    }

    function _checkOpportunityAggregate(uint256 sessionId, address trainer) internal view returns(bool){
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 currentRound = _sessions[key].info.currentRound;
        for (uint256 i = 0; i < _candidateAggregator[sessionId][currentRound].length; i++){
            if (
                _candidateAggregator[sessionId][currentRound][i] == trainer
                && _sessions[key].aggregator ==  address(0)
                && _trainerDetails[sessionId][currentRound][trainer].status == Session.TrainerStatus.Tested
                )
            {
                return true;
            }
        }
        return false;
    }
    function checkOpportunityAggregate(uint256 sessionId) external view override returns(bool){
        return _checkOpportunityAggregate(sessionId, msg.sender);
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
        require((_keyOfSessionDetailBySessionId[sessionId] == 0 && _sessions.length > 0) || _sessions.length == 0);
        Session.Detail memory sDetail;
        sDetail.info.sessionId = sessionId;
        sDetail.info.owner = msg.sender;
        sDetail.info.status = Session.RoundStatus.Ready;
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
        _sessionKeysByOwner[msg.sender].push(_sessions.length - 1);
        _randomTestingFactor[sessionId] = Random.randomNumber(maxTrainerInOneRound - 1) + 1;

        uint256 totalReward = msg.value * 10**REWARD_DECIMAL;
        balanceFeTokenInSession[sessionId] = totalReward;

        emit SessionCreated(msg.sender, sessionId, totalReward);
    }
    function removeSession(uint256 sessionId) external lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.owner == msg.sender);
        require(_sessions[key].info.status == Session.RoundStatus.Ready);
        uint256 rewardRemaining = balanceFeTokenInSession[sessionId] / (10**REWARD_DECIMAL);
        balanceFeTokenInSession[sessionId] = 0;
        _sessions[key].info.currentRound = _sessions[key].info.maxRound;
        _sessions[key].info.status = Session.RoundStatus.End;
        payable(msg.sender).transfer(rewardRemaining);

        emit SessionRemoved(msg.sender, sessionId, rewardRemaining);
    }









    function _checkSessionJoined(uint256 sessionId, address applier) internal view returns(bool){
        for (uint256 i = 0; i < _sessionJoined[applier].length; i++){
            if (_sessionJoined[applier][i] == sessionId){
                return false;
            }
        }
        return true;
    }
    function applySession(uint256 sessionId) external override {
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        require(_numCurrentSessionJoined[msg.sender] <= MAX_SESSION_APPLY_SAME_TIME);
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.owner != msg.sender);
        require(_sessions[key].info.status == Session.RoundStatus.Ready);
        uint256 currentRound = _sessions[key].info.currentRound;
        _trainers[sessionId][currentRound].push(msg.sender);
        if (_checkSessionJoined(sessionId, msg.sender))
        {
            _sessionJoined[msg.sender].push(sessionId);
        }
        _numCurrentSessionJoined[msg.sender] += 1;
        _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Training;
        _trainerDetails[sessionId][currentRound][msg.sender].indexInTrainerList = _trainers[sessionId][currentRound].length;
        if (_trainers[sessionId][currentRound].length == _sessions[key].info.maxTrainerInOneRound){
            _sessions[key].info.status = Session.RoundStatus.Training;
        }
    }
    function getDataDoTraining(uint256 sessionId) external view override returns(uint256, uint256){
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Training);
        return (_sessions[key].globalModelId, _sessions[key].latestGlobalModelParamId);
    }
    function _receiveBaseTrainingReward(address trainer, uint256 sessionKey) internal {
        uint256 sessionId = _sessions[sessionKey].info.sessionId;
        uint256 reward = _sessions[sessionKey].info.baseReward.trainingReward;
        _feToken.mint(trainer, reward);
        unchecked{
            balanceFeTokenInSession[sessionId] -= reward;
        }
    }
    function submitUpdate(uint256 sessionId, uint256 updateId) external lock override{
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Training);
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Training);
        _trainerDetails[sessionId][currentRound][msg.sender].updateId = updateId;
        _trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Trained;
        _sessions[key].numberOfTrainingSubmitted += 1;

        _receiveBaseTrainingReward(msg.sender, key);
        
        if (_sessions[key].numberOfTrainingSubmitted == _sessions[key].info.maxTrainerInOneRound)
        {
            _sessions[key].info.status = Session.RoundStatus.Scoring;
        }
    }







    function applyTesting(uint256 sessionId) external override {
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Scoring);
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Trained);
        _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Testing;
    }
    /**rtf = [1-4] = 1
     * 
     * 0,1,2,3,4
     * 
     * k0 = 1,2,3,4
     * k1 = 2,3,4,0
     * k2 = 3,4,0,1
     * k3 = 4,0,1,2
     * k4 = 0,1,2,3
     * 
     * rtf = [1-9] = 3
     * 
     * 0,1,2,3,4,5,6,7,8,9
     * 
     * k0 = 3,6,9,2
     * k1 = 4,7,0,3
     * k2 = 5,8,1,4
     * k3 = 6,9,2,5
     * k4 = 7,0,3,6
     * k5 = 8,1,4,7
     * k6 = 9,2,5,8
     * k7 = 0,3,6,9
     * k8 = 1,4,7,0
     * k9 = 2,5,8,1
     */
    function _getIndexTrainerSelectedForTest(
        uint256 sessionId,
        uint256 lenTrainerList,
        uint256 indexTester
    ) internal view returns(uint256[] memory indexs)
    {
        indexs = new uint256[](MIN_TRAINER_IN_ROUND - 1);

        indexs[0] = (indexTester + _randomTestingFactor[sessionId] > lenTrainerList)
                        ? (indexTester + _randomTestingFactor[sessionId]) % lenTrainerList - 1
                        : indexTester + _randomTestingFactor[sessionId];

        for (uint256 i = 1 ; i < (MIN_TRAINER_IN_ROUND - 1); i++){
            indexs[i] = (indexs[i-1] + _randomTestingFactor[sessionId] > lenTrainerList)
                        ? (indexs[i-1] + _randomTestingFactor[sessionId]) % lenTrainerList - 1
                        : indexs[i-1] + _randomTestingFactor[sessionId];
        }
    }
    function getDataDoTesting(uint256 sessionId) external view override returns(uint256[] memory){
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Scoring);
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Testing);
        
        uint256[] memory updateIds = new uint256[](MIN_TRAINER_IN_ROUND - 1);
        
        uint256 indexSender = _trainerDetails[sessionId][currentRound][msg.sender].indexInTrainerList;
        uint256 lenTrainerList = _trainers[sessionId][currentRound].length;
        uint256[] memory indexOfTrainerListSelectedForTesting = _getIndexTrainerSelectedForTest(sessionId, lenTrainerList, indexSender);
        
        for (uint256 i = 0; i < updateIds.length; i++){
            updateIds[i] = indexOfTrainerListSelectedForTesting[i];
        }
        return updateIds;
    }
    function _receiveBaseTestingReward(address trainer, uint256 sessionKey) internal {
        uint256 sessionId = _sessions[sessionKey].info.sessionId;
        uint256 reward = _sessions[sessionKey].info.baseReward.testingReward;
        _feToken.mint(trainer, reward);
        unchecked {
            balanceFeTokenInSession[sessionId] -= reward;
        }
    }
    function _checkNotBadScores(Session.scoreObject memory score) internal pure returns(bool){
        return (score.accuracy != 0
                && score.loss != 0
                && score.precision != 0
                && score.recall != 0
                && score.f1 != 0);
    }
    function _updateScore(Session.scoreObject memory updateScore, Session.scoreObject memory oldScore) internal pure returns(Session.scoreObject memory newScore){
        newScore = Session.scoreObject(
        updateScore.accuracy + oldScore.accuracy,
        updateScore.loss + oldScore.loss,
        updateScore.precision + oldScore.precision,
        updateScore.recall + oldScore.recall,
        updateScore.f1 + oldScore.f1);
    }
    function submitScores(uint256 sessionId, uint256[] memory scores) external lock override {
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Scoring);
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Testing);
        _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Tested;
        _sessions[key].numberOfTestingSubmitted += 1;
        uint256 indexSender = _trainerDetails[sessionId][currentRound][msg.sender].indexInTrainerList;
        uint256 lenTrainerList = _trainers[sessionId][currentRound].length;
        uint256[] memory indexOfTrainerListSelectedForTesting = _getIndexTrainerSelectedForTest(sessionId, lenTrainerList, indexSender);
        for(uint256 i = 0; i < indexOfTrainerListSelectedForTesting.length; i++){
            Session.scoreObject memory _scoreObj = Session.scoreObject(
            scores[0 + i*5],
            scores[1 + i*5],
            scores[2 + i*5],
            scores[3 + i*5],
            scores[4 + i*5]
            );
            address trainerSelected = _trainers[sessionId][currentRound][indexOfTrainerListSelectedForTesting[i]];
            Session.scoreObject memory currentScores = _trainerDetails[sessionId][currentRound][trainerSelected].scores;
            _trainerDetails[sessionId][currentRound][trainerSelected].scores = _updateScore(_scoreObj, currentScores);
            if (!_checkNotBadScores(_scoreObj)){
                _trainerDetails[sessionId][currentRound][trainerSelected].trainerReportedBadUpdateIdInTestingRound.push(msg.sender);
                if (_trainerDetails[sessionId][currentRound][trainerSelected].trainerReportedBadUpdateIdInTestingRound.length >= ERROR_VOTE_REPORTED)
                {
                    unchecked {
                        _sessions[key].numberOfErrorTrainerUpdateId += 1;
                    }
                }
            }
        }
        _receiveBaseTestingReward(msg.sender, key);
        if (_sessions[key].numberOfTestingSubmitted == _sessions[key].info.maxTrainerInOneRound)
        {
            _sessions[key].info.status = Session.RoundStatus.Aggregating;
        }
    }









    
    function selectCandidateAggregator(uint256 sessionId) external view override returns(address[] memory) {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.owner == msg.sender);
        require(_sessions[key].info.status == Session.RoundStatus.Aggregating);
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_candidateAggregator[sessionId][currentRound].length == 0);

        address[] memory candidates = new address[](MUN_CANDIDATE_AGGREGATOR);
        uint256[] memory balanceOfCandidates = new uint256[](MUN_CANDIDATE_AGGREGATOR);
        
        for (uint256 i = 0; i < _sessions[key].info.maxTrainerInOneRound; i++){
            address trainer = _trainers[sessionId][currentRound][i];
            if (_trainerDetails[sessionId][currentRound][trainer].trainerReportedBadUpdateIdInTestingRound.length >= ERROR_VOTE_REPORTED){
                continue;
            }
            uint256 balanceOf = _feToken.balanceOf(trainer);
            for (uint256 j = 0; j < MUN_CANDIDATE_AGGREGATOR; j++){
                if (balanceOf >= balanceOfCandidates[j])
                {
                    for (uint256 k = MUN_CANDIDATE_AGGREGATOR - 1; k > j; k--){
                        if (balanceOfCandidates[j+1] == 0){
                            break;
                        }
                        balanceOfCandidates[k] = balanceOfCandidates[k-1];
                        candidates[k] = candidates[k-1];
                    }
                    balanceOfCandidates[j] = balanceOf;
                    candidates[j] = trainer;
                }
            }
        }
        return candidates;
    }
    function _checkCandidateIsTrainerInSession(uint256 sessionKey, uint256 currentRound, address[] memory candidates) internal view returns(bool){
        for (uint256 i = 0; i < candidates.length; i++){
            if (_trainerDetails[sessionKey][currentRound][candidates[i]].status != Session.TrainerStatus.Tested){
                return false;
            }
        }
        return true;
    }
    function submitCandidateAggregator(uint256 sessionId, address[] memory candidates) external override {
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.owner == msg.sender);
        require(_sessions[key].info.status == Session.RoundStatus.Aggregating);
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_candidateAggregator[sessionId][currentRound].length == 0);
        require(_checkCandidateIsTrainerInSession(key, currentRound, candidates));
        _candidateAggregator[sessionId][currentRound] = candidates;
    } 

    function applyAggregator(uint256 sessionId) external override {
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Aggregating);
        require(_checkOpportunityAggregate(sessionId, msg.sender));
        _sessions[key].aggregator = msg.sender;
        _sessions[key].info.status = Session.RoundStatus.Aggregating;
        uint256 currentRound = _sessions[key].info.currentRound;
        _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Aggregating;
    }
    function getDataDoAggregate(uint256 sessionId) external view returns(uint256[] memory) {
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Aggregating);
        uint256 len = _trainers[sessionId][currentRound].length;
        uint256[] memory updateModelParamIds = new uint256[](len);
        for (uint256 i = 0; i < len; i++){
            address trainer  = _trainers[sessionId][currentRound][i];
            updateModelParamIds[i] = _trainerDetails[sessionId][currentRound][trainer].updateId;
        }
        return updateModelParamIds;
    }
    function _receiveBaseAggregateReward(address aggregator, uint256 sessionKey) internal {
        uint256 sessionId = _sessions[sessionKey].info.sessionId;
        uint256 reward = _sessions[sessionKey].info.baseReward.aggregateReward;
        _feToken.mint(aggregator, reward);
        unchecked {
            balanceFeTokenInSession[sessionId] -= reward;
        }
    }
    function _resetRound(uint256 sessionId, uint256 sessionKey, uint256 currentRound) internal {
        for (uint256 i = 0; i < _sessions[sessionKey].info.maxTrainerInOneRound; i++){
            address trainer = _trainers[sessionId][currentRound][i];
            unchecked {
                _numCurrentSessionJoined[trainer] -= 1;
            }
        }
        _sessions[sessionKey].info.status = Session.RoundStatus.Training;
        _sessions[sessionKey].numberOfTrainingSubmitted = 0;
        _sessions[sessionKey].numberOfTestingSubmitted = 0;
        _sessions[sessionKey].numberOfErrorTrainerUpdateId = 0;
        _sessions[sessionKey].aggregator = address(0);
    }
    function submitAggregate(uint256 sessionId, uint256 updateId, uint256[] memory indexOfTrainerHasBadUpdateId) external lock override {
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Aggregating);
        uint256 countErrorUpdateIdInAggregatingRound;
        uint256 numberOfErrorTrainerUpdateId = _sessions[key].numberOfErrorTrainerUpdateId;
        if (indexOfTrainerHasBadUpdateId.length >= numberOfErrorTrainerUpdateId){
            for (uint256 i = 0; i < indexOfTrainerHasBadUpdateId.length; i++){
                uint256 index = indexOfTrainerHasBadUpdateId[i];
                address trainer = _trainers[sessionId][currentRound][index];
                if(_trainerDetails[sessionId][currentRound][trainer].trainerReportedBadUpdateIdInTestingRound.length >= ERROR_VOTE_REPORTED){
                    unchecked {
                        countErrorUpdateIdInAggregatingRound += 1;
                    }
                    _trainerDetails[sessionId][currentRound][trainer].status = Session.TrainerStatus.TrainedFaild;
                }
                _trainerDetails[sessionId][currentRound][trainer].aggregatorReportedBadUpdateIdInAggregateRound = true;
            }
        }
        if (countErrorUpdateIdInAggregatingRound == numberOfErrorTrainerUpdateId){
            _sessions[key].latestGlobalModelParamId = updateId;
            _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Aggregated;
            _receiveBaseAggregateReward(msg.sender, key);
            if (_sessions[key].info.currentRound == _sessions[key].info.maxRound){
                _sessions[key].info.status = Session.RoundStatus.End;
            }
            else
            {
                unchecked {
                    _sessions[key].info.currentRound += 1;
                }
                _sessions[key].info.status = Session.RoundStatus.Ready;
                _resetRound(sessionId, key, currentRound - 1);
            }
        }
        else {
            _sessions[key].aggregator = address(0);
            _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.AggregatedFaild;
        }
    }
    function withdraw(uint256 amountETH) external lock override {
        uint256 amountFeToken = amountETH *(10**REWARD_DECIMAL);
        require(amountFeToken <= _feToken.balanceOf(msg.sender));
        _feToken.burn(msg.sender, amountFeToken);
        payable(msg.sender).transfer(amountETH);
    }
}
/**
 * 10 => 70
 * 
 */