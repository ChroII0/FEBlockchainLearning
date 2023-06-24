// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/IFEBlockchainLearning.sol";
import "./interfaces/ITrainerManagement.sol";
import "./interfaces/IAdminControlMetadata.sol";
import "./interfaces/ITimeLock.sol";
import "./interfaces/IFEToken.sol";
import "./libraries/Session.sol";
import "./libraries/Random.sol";


contract FEBlockchainLearning is IFEBlockchainLearning {
    using Random for *;

    Session.Detail[] private _sessions;
    // sessionId => rtf
    mapping (uint256 => uint256) private _randomFactor;
    // owner => sessionKey[]
    mapping (address => uint256[]) private _sessionKeysByOwner;
    // ownerSession => balanceFeToken
    mapping (uint256 => uint256) public balanceFeTokenInSession;
    // trainer => sessionId => amount
    mapping (address => mapping (uint256 => uint256)) public amountStakes;
    // trainer => sessionId[]
    mapping (address => uint256[]) private _sessionJoined;
    // trainer => num current session joined
    mapping (address => uint256) private _numCurrentSessionJoined;
    // trainer => sessionId => bool
    mapping (address => mapping (uint256 => bool)) private _isJoined;
    // sessionId => key
    mapping (uint256 => uint256) private _keyOfSessionDetailBySessionId;
    // sessionId => round => trainer[]
    mapping (uint256 => mapping (uint256 => address[])) private _trainers;
    // sessionId => round => trainer 
    mapping (uint256 => mapping (uint256 => mapping (address => Session.TrainerDetail))) private _trainerDetails;
    // sessionId => round => candidateAggregator[]
    mapping (uint256 => mapping (uint256 => address[])) private _candidateAggregator;

    uint256 public constant MAX_SESSION_APPLY_SAME_TIME = 5;
    uint256 public constant MUN_CANDIDATE_AGGREGATOR = 5;
    uint256 public MIN_ROUND = 1;
    uint256 public MAX_ROUND = 10;
    uint256 public MIN_TRAINER_IN_ROUND = 5;
    uint256 public MAX_TRAINER_IN_ROUND = 100;
    uint256 public MIN_REWARD = MIN_ROUND * MIN_TRAINER_IN_ROUND * (10**REWARD_DECIMAL);
    uint256 public ERROR_VOTE_REPORTED = (MIN_TRAINER_IN_ROUND - 1)/2 + (MIN_TRAINER_IN_ROUND - 1)%2;

    uint256 public constant REWARD_DECIMAL = 4;
    uint256 public constant SCORES_DECIMAL = 5;
    uint256 public BASE_TRAINING_REWARD_RATE = 500; // 5%
    uint256 public BASE_CHECKING_REWARD_RATE = 500; // 5%
    uint256 public BASE_AGGREGATE_REWARD_RATE = 500; // 5%m
    uint256 public BASE_TESTING_REWARD_RATE = 500; // 5%
    uint256 public PERFORMANCE_REWARD_RATE = 10**REWARD_DECIMAL - (BASE_TRAINING_REWARD_RATE + BASE_CHECKING_REWARD_RATE + BASE_TESTING_REWARD_RATE + BASE_AGGREGATE_REWARD_RATE);

    ITrainerManagement private _trainerManagement;
    IAdminControlMetadata private _adminControl;
    ITimeLock private _timeLock;
    IFEToken private _feToken;

    constructor(address adminControl, address trainerManagementAddress, address timeLock, address feToken) {
        _trainerManagement = ITrainerManagement(trainerManagementAddress);
        _adminControl = IAdminControlMetadata(adminControl);
        _timeLock = ITimeLock(timeLock);
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
        MIN_REWARD = MIN_ROUND * MIN_TRAINER_IN_ROUND * (10**REWARD_DECIMAL);
    }
    function setNumTrainerInRound(uint256 newMinTrainerInRound, uint256 newMaxTrainerInRound) external override onlyAdmin(msg.sender) {
        require(newMaxTrainerInRound > newMinTrainerInRound && newMinTrainerInRound >= MUN_CANDIDATE_AGGREGATOR);
        MIN_TRAINER_IN_ROUND = newMinTrainerInRound;
        MAX_TRAINER_IN_ROUND = newMaxTrainerInRound;
        ERROR_VOTE_REPORTED = (MIN_TRAINER_IN_ROUND - 1)/2 + (MIN_TRAINER_IN_ROUND - 1)%2;
        MIN_REWARD = MIN_ROUND * MIN_TRAINER_IN_ROUND * (10**REWARD_DECIMAL);
    }
    function setBaseRewardRate(
        uint256 baseTrainingRewardRate,
        uint256 baseCheckingRewardRate,
        uint256 baseAggregatingRewardRate,
        uint256 baseTestingRewardRate
        ) external override onlyAdmin(msg.sender){
        require(baseTrainingRewardRate > 0);
        require(baseCheckingRewardRate > 0);
        require(baseAggregatingRewardRate > 0);
        require(baseTestingRewardRate > 0);
        require(
            baseTrainingRewardRate + 
            baseCheckingRewardRate + 
            baseAggregatingRewardRate + 
            baseTestingRewardRate < 10**REWARD_DECIMAL);
        BASE_TRAINING_REWARD_RATE = baseTrainingRewardRate;
        BASE_CHECKING_REWARD_RATE = baseCheckingRewardRate;
        BASE_AGGREGATE_REWARD_RATE = baseAggregatingRewardRate;
        BASE_TESTING_REWARD_RATE = baseTestingRewardRate;
        PERFORMANCE_REWARD_RATE = 10**REWARD_DECIMAL - (BASE_TRAINING_REWARD_RATE + BASE_CHECKING_REWARD_RATE + BASE_TESTING_REWARD_RATE + BASE_AGGREGATE_REWARD_RATE);
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
        uint256 latestGlobalModelParamId,
        uint256 expirationTimeOfTrainingRound,
        uint256 expirationTimeOfCheckingRound,
        uint256 expirationTimeOfAggregatingRound,
        uint256 expirationTimeOfTestingRound
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

        _timeLock.setExpirationTimeOfEachRoundInSession(
            sessionId,
            expirationTimeOfTrainingRound,
            expirationTimeOfCheckingRound,
            expirationTimeOfAggregatingRound,
            expirationTimeOfTestingRound
        );

        _sessions.push(sDetail);
        _keyOfSessionDetailBySessionId[sessionId] = _sessions.length - 1;
        _sessionKeysByOwner[msg.sender].push(_sessions.length - 1);
        _randomFactor[sessionId] = Random.randomNumber(2**42 - 1);

        uint256 totalReward = msg.value * 10**REWARD_DECIMAL;
        balanceFeTokenInSession[sessionId] = totalReward;

        emit SessionCreated(msg.sender, sessionId, totalReward);
    }
    //FIXME: 
    function removeSession(uint256 sessionId) external lock override {
        // uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        // require(_sessions[key].info.owner == msg.sender);
        // require(_sessions[key].info.status == Session.RoundStatus.Ready);
        // uint256 rewardRemaining = balanceFeTokenInSession[sessionId] / (10**REWARD_DECIMAL);
        // balanceFeTokenInSession[sessionId] = 0;
        // _sessions[key].info.currentRound = _sessions[key].info.maxRound;
        // _sessions[key].info.status = Session.RoundStatus.End;
        // payable(msg.sender).transfer(rewardRemaining);

        // emit SessionRemoved(msg.sender, sessionId, rewardRemaining);
    }









    function applySession(uint256 sessionId) external payable lock override {
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        require(_numCurrentSessionJoined[msg.sender] <= MAX_SESSION_APPLY_SAME_TIME);
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.owner != msg.sender);
        require(_sessions[key].info.status == Session.RoundStatus.Ready);
        uint256 amountStake = msg.value * (10**REWARD_DECIMAL);
        require(amountStake == _sessions[key].info.maxTrainerInOneRound ** _sessions[key].info.baseReward.trainingReward);
        uint256 currentRound = _sessions[key].info.currentRound;
        _trainers[sessionId][currentRound].push(msg.sender);
        if (!_isJoined[msg.sender][sessionId])
        {
            _sessionJoined[msg.sender].push(sessionId);
            _isJoined[msg.sender][sessionId] = true;
        }
        unchecked {
            _numCurrentSessionJoined[msg.sender] += 1;
        }
        _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Training;
        _trainerDetails[sessionId][currentRound][msg.sender].indexInTrainerList = _trainers[sessionId][currentRound].length;
        amountStakes[msg.sender][sessionId] = amountStake;
        if (_trainers[sessionId][currentRound].length == _sessions[key].info.maxTrainerInOneRound){
            _sessions[key].info.status = Session.RoundStatus.Training;
            _timeLock.setTrainingRoundStartTime(sessionId);
        }
    }
    function outApplySession(uint256 sessionId) external lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Training);
        require(_sessions[key].info.status == Session.RoundStatus.Ready);
        
        _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Unavailable;
        
        uint256 indexSender = _trainerDetails[sessionId][currentRound][msg.sender].indexInTrainerList;
        uint256 indexLastTrainer = _trainers[sessionId][currentRound].length - 1;
        address lastTrainer = _trainers[sessionId][currentRound][indexLastTrainer];
        
        _trainers[sessionId][currentRound][indexSender] = _trainers[sessionId][currentRound][indexLastTrainer];
        _trainers[sessionId][currentRound].pop();
        _trainerDetails[sessionId][currentRound][lastTrainer].indexInTrainerList = indexSender;
        
        uint256 amountStake = amountStakes[msg.sender][sessionId];
        amountStakes[msg.sender][sessionId] = 0;
        _feToken.mint(msg.sender, amountStake);
        unchecked {
            _numCurrentSessionJoined[msg.sender] -= 1;
        }
    }


    





    function getDataDoTraining(uint256 sessionId) external view override returns(uint256, uint256){
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Training);
        require(_sessions[key].info.status == Session.RoundStatus.Training);
        require(_timeLock.checkExpirationTimeOfTrainingRound(sessionId));
        return (_sessions[key].globalModelId, _sessions[key].latestGlobalModelParamId);
    }
    function _receiveBaseTrainingRewardAndStakedAmount(address trainer, uint256 sessionKey) internal {
        uint256 sessionId = _sessions[sessionKey].info.sessionId;
        uint256 reward = _sessions[sessionKey].info.baseReward.trainingReward;
        uint256 amountStake = amountStakes[trainer][sessionId];
        amountStakes[trainer][sessionId] = 0;
        unchecked{
            balanceFeTokenInSession[sessionId] -= reward;
        }
        _feToken.mint(trainer, reward + amountStake);
    }
    function submitUpdate(uint256 sessionId, uint256 updateId) external payable lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Training);
        require(_timeLock.checkExpirationTimeOfTrainingRound(sessionId));
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Training);
        uint256 amountStake = msg.value * (10**REWARD_DECIMAL);
        require(amountStake == _sessions[key].info.maxTrainerInOneRound ** _sessions[key].info.baseReward.checkingReward);

        _trainerDetails[sessionId][currentRound][msg.sender].updateId = updateId;
        _trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Trained;
        unchecked {
            _sessions[key].countSubmitted += 1;
        }

        _receiveBaseTrainingRewardAndStakedAmount(msg.sender, key);
        amountStakes[msg.sender][sessionId] = amountStake;
        
        if (_sessions[key].countSubmitted == _sessions[key].info.maxTrainerInOneRound)
        {
            _sessions[key].info.status = Session.RoundStatus.Checking;
            _sessions[key].countSubmitted = 0;
            _timeLock.setTrainingRoundStartTime(sessionId);
        }
    }
    function refundStakeCheckingRound(uint256 sessionId) external lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Training);
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Trained);
        require(_timeLock.checkExpirationTimeOfTrainingRound(sessionId) == false);
        _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Unavailable;
        uint256 amountStake = amountStakes[msg.sender][sessionId];
        amountStakes[msg.sender][sessionId] = 0;
        _feToken.mint(msg.sender, amountStake);
        unchecked {
            _numCurrentSessionJoined[msg.sender] -= 1;
        }
    }
    


















    function _getIndexTrainerSelectedForRandom(
        uint256 sessionId,
        uint256 currentRound,
        address sender,
        Session.RoundStatus roundStatus
    ) internal view returns(uint256[] memory indexs)
    {

        uint256 indexSender = _trainerDetails[sessionId][currentRound][sender].indexInTrainerList;
        uint256 lenTrainerList = _trainers[sessionId][currentRound].length;
        uint256 seedForRound = uint256(keccak256(abi.encodePacked(roundStatus))) % lenTrainerList;
        indexs = new uint256[](MIN_TRAINER_IN_ROUND - 1);

        indexs[0] = (indexSender + _randomFactor[sessionId] % lenTrainerList + seedForRound > lenTrainerList)
                        ? (indexSender + _randomFactor[sessionId] % lenTrainerList + seedForRound) % lenTrainerList - 1
                        : indexSender + _randomFactor[sessionId] % lenTrainerList + seedForRound;

        for (uint256 i = 1 ; i < (MIN_TRAINER_IN_ROUND - 1); i++){
            indexs[i] = (indexs[i-1] + _randomFactor[sessionId] % lenTrainerList + seedForRound > lenTrainerList)
                        ? (indexs[i-1] + _randomFactor[sessionId] % lenTrainerList + seedForRound) % lenTrainerList - 1
                        : indexs[i-1] + _randomFactor[sessionId] % lenTrainerList + seedForRound;
        }
    }

    function _getDataForRandom(uint256 sessionId, uint256 currentRound, Session.RoundStatus roundStatus, address sender) internal view returns(uint256[] memory) {
        uint256[] memory updateIds = new uint256[](MIN_TRAINER_IN_ROUND - 1);

        uint256[] memory indexOfTrainerListSelectedForChecking = _getIndexTrainerSelectedForRandom(sessionId, currentRound, sender, roundStatus);
        
        for (uint256 i = 0; i < updateIds.length; i++){
            uint256 indexTrainerSelected = indexOfTrainerListSelectedForChecking[i];
            address trainerSelected = _trainers[sessionId][currentRound][indexTrainerSelected];
            updateIds[i] = _trainerDetails[sessionId][currentRound][trainerSelected].updateId;
        }
        return updateIds;
    }

    function getDataDoChecking(uint256 sessionId) external view override returns(uint256[] memory) {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Checking);
        require(_timeLock.checkExpirationTimeOfCheckingRound(sessionId));
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Trained);

        return _getDataForRandom(sessionId, currentRound, Session.RoundStatus.Checking, msg.sender);
    }
    function _receiveBaseCheckingRewardAndStakedAmount(address trainer, uint256 sessionKey) internal {
        uint256 sessionId = _sessions[sessionKey].info.sessionId;
        uint256 reward = _sessions[sessionKey].info.baseReward.checkingReward;
        uint256 amountStake = amountStakes[trainer][sessionId];
        amountStakes[trainer][sessionId] = 0;
        unchecked{
            balanceFeTokenInSession[sessionId] -= reward;
        }
        _feToken.mint(trainer, reward + amountStake);
    }
    // function _checkBadTrainer(uint256 countReport) internal view returns(bool){
    //     return (countReport >= ERROR_VOTE_REPORTED);
    // }
    function submitCheckingResult(uint256 sessionId, bool[] memory result) external payable lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Checking);
        require(_timeLock.checkExpirationTimeOfCheckingRound(sessionId));
        require(result.length == (MIN_TRAINER_IN_ROUND - 1));
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Trained);
        uint256 amountStake = msg.value * (10**REWARD_DECIMAL);
        require(amountStake == _sessions[key].info.maxTrainerInOneRound ** _sessions[key].info.baseReward.testingReward);

        uint256[] memory indexOfTrainerListSelectedForChecking = _getIndexTrainerSelectedForRandom(
                                                                                sessionId,
                                                                                currentRound,
                                                                                msg.sender,
                                                                                Session.RoundStatus.Checking);
        for (uint256 i = 0; i < result.length; i++){
            if (!result[i]){
                address trainer = _trainers[sessionId][currentRound][indexOfTrainerListSelectedForChecking[i]];
                _trainerDetails[sessionId][currentRound][trainer].trainerReportedBadUpdateIdInCheckingRound.push(msg.sender);
            }
        }
        unchecked {
            _sessions[key].countSubmitted += 1;
        }
        _receiveBaseCheckingRewardAndStakedAmount(msg.sender, key);
        amountStakes[msg.sender][sessionId] = amountStake;

        if (_sessions[key].countSubmitted == _sessions[key].info.maxTrainerInOneRound)
        {
            _sessions[key].info.status = Session.RoundStatus.Checked;
            _sessions[key].countSubmitted = 0;
            _timeLock.setTrainingRoundStartTime(sessionId);
        }
    }


    // function applyTesting(uint256 sessionId) external override {
    //     require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
    //     uint256 key = _keyOfSessionDetailBySessionId[sessionId];
    //     require(_sessions[key].info.status == Session.RoundStatus.Testing);
    //     uint256 currentRound = _sessions[key].info.currentRound;
    //     require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Trained);
    //     _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Testing;
    // }


























    function getDataDoTesting(uint256 sessionId) external view override returns(uint256[] memory){
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Testing);
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Testing);
        
        return _getDataForRandom(sessionId, currentRound, Session.RoundStatus.Testing, msg.sender);
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
        require(_sessions[key].info.status == Session.RoundStatus.Testing);
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Testing);
        _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Tested;
        _sessions[key].countSubmitted += 1;
        // uint256 indexSender = _trainerDetails[sessionId][currentRound][msg.sender].indexInTrainerList;
        // uint256 lenTrainerList = _trainers[sessionId][currentRound].length;
        uint256[] memory indexOfTrainerListSelectedForTesting = _getIndexTrainerSelectedForRandom(sessionId, currentRound, msg.sender, Session.RoundStatus.Testing);
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
        if (_sessions[key].countSubmitted == _sessions[key].info.maxTrainerInOneRound)
        {
            _sessions[key].info.status = Session.RoundStatus.Aggregating;
        }
    }









    /**
     *      
     * 
     * 
     */
    function _encodeCandidates(uint256[] memory values, uint256 rf) internal pure returns (uint256 value) {
        uint256 bitIndex = 90;
        value |= rf;
        for (uint256 i = 0; i < values.length; i++){
            value |= values[i] << bitIndex;
            bitIndex += 15;
        }
        value *= rf;
    }
    function _decodeCandidates(uint256 value, uint256 rf) internal pure returns(uint256[] memory values) {
        value /= rf;
        uint256 bitIndex = 0;
        values[0] = (((2**90 - 1) << bitIndex) & value) >> bitIndex;
        bitIndex += 90;
        for (uint256 i = 1; i < (MUN_CANDIDATE_AGGREGATOR + 1); i++){
            values[i] = (((2**15 - 1) << bitIndex) & value) >> bitIndex;
            bitIndex += 15;
        }
    }
    function selectCandidateAggregator(uint256 sessionId) external view override returns(uint256 candidatesEncode) {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.owner == msg.sender);
        require(_sessions[key].info.status == Session.RoundStatus.Checked);
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_candidateAggregator[sessionId][currentRound].length == 0);

        uint256[] memory candidates = new uint256[](MUN_CANDIDATE_AGGREGATOR);
        uint256[] memory balanceOfCandidates = new uint256[](MUN_CANDIDATE_AGGREGATOR);
        
        for (uint256 i = 0; i < _sessions[key].info.maxTrainerInOneRound; i++){
            address trainer = _trainers[sessionId][currentRound][i];
            if (_trainerDetails[sessionId][currentRound][trainer].trainerReportedBadUpdateIdInCheckingRound.length >= ERROR_VOTE_REPORTED){
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
                        candidates[k] = k-1;
                    }
                    balanceOfCandidates[j] = balanceOf;
                    candidates[j] = i;
                }
            }
        }
        return _encodeCandidates(candidates, _randomFactor[sessionId]);
    }
    function _checkCandidateIsTrainerInSession(uint256 sessionKey, uint256 currentRound, address[] memory candidates) internal view returns(bool){
        for (uint256 i = 0; i < candidates.length; i++){
            if (_trainerDetails[sessionKey][currentRound][candidates[i]].status != Session.TrainerStatus.Checked){
                return false;
            }
        }
        return true;
    }
    function submitCandidateAggregator(uint256 sessionId, uint256 candidatesEncode) external override {
        require(_trainerManagement.isAllowed(msg.sender) == true, "You are not allowed");
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.owner == msg.sender);
        require(_sessions[key].info.status == Session.RoundStatus.Checked);
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_candidateAggregator[sessionId][currentRound].length == 0);

        uint256[] memory candidates = _decodeCandidates(candidatesEncode, _randomFactor[sessionId]);
        require(candidates[0] == _randomFactor[sessionId]);
        
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
        _sessions[sessionKey].countSubmitted = 0;
        _sessions[sessionKey].countSubmitted = 0;
        _sessions[sessionKey].numberOfErrorTrainerUpdateId = 0;
        _sessions[sessionKey].aggregator = address(0);
    }
    function _checkBadTester(uint256 sessionId, uint256 currentRound) internal {
        for (uint256 i = 0; i < _trainers[sessionId][currentRound].length; i++){
            address trainer = _trainers[sessionId][currentRound][i];
            if (_trainerDetails[sessionId][currentRound][trainer].trainerReportedBadUpdateIdInTestingRound.length == 1
                && _trainerDetails[sessionId][currentRound][trainer].aggregatorReportedBadUpdateIdInAggregateRound == false
            ){
                address tester = _trainerDetails[sessionId][currentRound][trainer].trainerReportedBadUpdateIdInTestingRound[0];
                if (_trainerDetails[sessionId][currentRound][tester].status == Session.TrainerStatus.TrainedFailed)
                {
                    _trainerDetails[sessionId][currentRound][tester].status = Session.TrainerStatus.TrainedAndTestedFailed;
                }
                else
                {
                    _trainerDetails[sessionId][currentRound][tester].status = Session.TrainerStatus.TestedFailed;
                }
            }
        }
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
                    _trainerDetails[sessionId][currentRound][trainer].status = Session.TrainerStatus.TrainedFailed;
                }
                _trainerDetails[sessionId][currentRound][trainer].aggregatorReportedBadUpdateIdInAggregateRound = true;
            }
        }
        if (countErrorUpdateIdInAggregatingRound == numberOfErrorTrainerUpdateId){
            _checkBadTester(sessionId, currentRound);
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
            _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.AggregatedFailed;
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