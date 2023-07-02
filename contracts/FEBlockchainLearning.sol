// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/IFEBlockchainLearning.sol";
import "./interfaces/ITrainerManagement.sol";
import "./interfaces/IAdminControlMetadata.sol";
import "./interfaces/ITimeLock.sol";
import "./interfaces/IPerformanceRewardDistribution.sol";
import "./interfaces/IFEToken.sol";
import "./libraries/Session.sol";
import "./libraries/Random.sol";

abstract contract PerformanceRewardDistribution is IPerformanceRewardDistribution {
    function isClaim(address trainer, uint256 sessionId, uint256 round) public view virtual returns(bool);
}

contract FEBlockchainLearning is IFEBlockchainLearning {
    using Random for *;

    uint256 private immutable _secretValueRandom;

    Session.Detail[] private _sessions;
    // sessionId => rf
    mapping (uint256 => uint256) private _randomFactor;
    // owner => sessionKey[]
    mapping (address => uint256[]) private _sessionKeysByOwner;
    // sessionId => balanceFeToken
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
    // sessionId => round => indexCandidateAggregator[]
    mapping (uint256 => mapping (uint256 => uint256[])) private _indexCandidateAggregator;
    // sessionId => round => count scores
    mapping (uint256 => mapping (uint256 => uint256[])) public countScores;
    //
    mapping (uint256 => Session.DeadRound[]) private _deadRounds;

    uint256 public constant MAX_SESSION_APPLY_SAME_TIME = 5;
    uint256 public constant MUN_CANDIDATE_AGGREGATOR = 5;
    uint256 public MIN_ROUND = 1;
    uint256 public MAX_ROUND = 10;
    uint256 public MIN_TRAINER_IN_ROUND = 5;
    uint256 public MAX_TRAINER_IN_ROUND = 100;
    uint256 public MIN_REWARD = MAX_ROUND * MAX_TRAINER_IN_ROUND * (10**REWARD_DECIMAL);
    uint256 public ERROR_VOTE_REPORTED = (MIN_TRAINER_IN_ROUND - 1)/2 + (MIN_TRAINER_IN_ROUND - 1)%2;

    uint256 public constant REWARD_DECIMAL = 4;
    uint256 public BASE_TRAINING_REWARD_RATE = 500; // 5%
    uint256 public BASE_CHECKING_REWARD_RATE = 500; // 5%
    uint256 public BASE_AGGREGATE_REWARD_RATE = 500; // 5%
    uint256 public BASE_TESTING_REWARD_RATE = 500; // 5%
    uint256 public PERFORMANCE_REWARD_RATE = 10**REWARD_DECIMAL - (BASE_TRAINING_REWARD_RATE + BASE_CHECKING_REWARD_RATE + BASE_TESTING_REWARD_RATE + BASE_AGGREGATE_REWARD_RATE);

    ITrainerManagement private _trainerManagement;
    IAdminControlMetadata private _adminControl;
    ITimeLock private _timeLock;
    PerformanceRewardDistribution private _performanceRewardDistribution;
    IFEToken private _feToken;

    constructor(
        address adminControl, 
        address trainerManagementAddress, 
        address timeLock, 
        address performanceRewardDistribution,
        address feToken, 
        uint256 secretValueRandom)
        {

        _trainerManagement = ITrainerManagement(trainerManagementAddress);
        _adminControl = IAdminControlMetadata(adminControl);
        _timeLock = ITimeLock(timeLock);
        _feToken = IFEToken(feToken);
        _performanceRewardDistribution = PerformanceRewardDistribution(performanceRewardDistribution);
        _secretValueRandom = secretValueRandom;
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
        MIN_REWARD = MAX_ROUND * MAX_TRAINER_IN_ROUND * (10**REWARD_DECIMAL);
    }
    function setNumTrainerInRound(uint256 newMinTrainerInRound, uint256 newMaxTrainerInRound) external override onlyAdmin(msg.sender) {
        require(newMaxTrainerInRound > newMinTrainerInRound && newMinTrainerInRound >= MUN_CANDIDATE_AGGREGATOR);
        MIN_TRAINER_IN_ROUND = newMinTrainerInRound;
        MAX_TRAINER_IN_ROUND = newMaxTrainerInRound;
        ERROR_VOTE_REPORTED = (MIN_TRAINER_IN_ROUND - 1)/2 + (MIN_TRAINER_IN_ROUND - 1)%2;
        MIN_REWARD = MAX_ROUND * MAX_TRAINER_IN_ROUND * (10**REWARD_DECIMAL);
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
        uint256 indexTrainer  = _trainerDetails[sessionId][currentRound][trainer].indexInTrainerList;
        for (uint256 i = 0; i < _indexCandidateAggregator[sessionId][currentRound].length; i++){
            if (
                _indexCandidateAggregator[sessionId][currentRound][i] == indexTrainer
                && _sessions[key].indexAggregator ==  (MAX_TRAINER_IN_ROUND + 1)
                && _trainerDetails[sessionId][currentRound][trainer].status == Session.TrainerStatus.Checked
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
        uint256 valueRandomClientSide,
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
        sDetail.info.performanceReward = msg.value * PERFORMANCE_REWARD_RATE / maxRound;
        sDetail.info.baseReward.trainingReward = msg.value * BASE_TRAINING_REWARD_RATE / maxRound / maxTrainerInOneRound;
        sDetail.info.baseReward.checkingReward = msg.value * BASE_TESTING_REWARD_RATE / maxRound / maxTrainerInOneRound;
        sDetail.info.baseReward.aggregatingReward = msg.value * BASE_AGGREGATE_REWARD_RATE / maxRound;
        sDetail.info.baseReward.testingReward = msg.value * BASE_TESTING_REWARD_RATE / maxRound / maxTrainerInOneRound;
        sDetail.info.maxRound = maxRound;
        sDetail.info.maxTrainerInOneRound = maxTrainerInOneRound;
        sDetail.globalModelId = globalModelId;
        sDetail.latestGlobalModelParamId = latestGlobalModelParamId;
        sDetail.indexAggregator = MAX_TRAINER_IN_ROUND + 1;

        countScores[sessionId][0] = new uint256[](MIN_TRAINER_IN_ROUND);
        countScores[sessionId][0][0] = maxTrainerInOneRound;

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
        _randomFactor[sessionId] = Random.randomNumber(2**90 - 1, valueRandomClientSide, _secretValueRandom);

        uint256 totalReward = msg.value * 10**REWARD_DECIMAL;
        balanceFeTokenInSession[sessionId] = totalReward;

        emit SessionCreated(msg.sender, sessionId, totalReward);
    }

    function _calRefundAmount(
        address[] memory trainers,
        uint256 sessionId,
        uint256 currentRound,
        Session.TrainerStatus statusCheck,
        uint256 refundAmount
        ) internal returns(uint256 totalRefundAmount){
        for (uint256 i = 0; i < trainers.length; i ++){
            if (_trainerDetails[sessionId][currentRound][trainers[i]].status != statusCheck){
                unchecked {
                    totalRefundAmount += refundAmount;
                    amountStakes[trainers[i]][sessionId] -= refundAmount;
                }
                // if (amountStakes[trainers[i]][sessionId] > 0){
                    
                // }
                _trainerDetails[sessionId][currentRound][trainers[i]].status = Session.TrainerStatus.Unavailable;
            }
        }
    }
    function _replaceRound(uint256 sessionId, uint256 key, uint256 currentRound) internal {
        address[] memory candidates = new address[](MUN_CANDIDATE_AGGREGATOR);
        Session.TrainerStatus trainerStatusCheck;
        uint256 refundAmount;
        uint256 maxTrainerInOneRound = _sessions[key].info.maxTrainerInOneRound;
        Session.DeadRound memory deadRound;
        deadRound.round = currentRound;
        if (_sessions[key].info.status == Session.RoundStatus.Training){
            if (!_timeLock.checkExpirationTimeOfTrainingRound(sessionId)){
                trainerStatusCheck = Session.TrainerStatus.Trained;
                refundAmount = _sessions[key].info.baseReward.checkingReward * maxTrainerInOneRound;
                deadRound.status = Session.RoundStatus.Training;
            }else revert();
        }
        else if (_sessions[key].info.status == Session.RoundStatus.TrainingFailed){
            trainerStatusCheck = Session.TrainerStatus.Checked;
            refundAmount = _sessions[key].info.baseReward.trainingReward * 2;
            deadRound.status = Session.RoundStatus.Training;
        }
        else if (_sessions[key].info.status == Session.RoundStatus.Checking)
        {
            if (!_timeLock.checkExpirationTimeOfCheckingRound(sessionId)){
                trainerStatusCheck = Session.TrainerStatus.Checked;
                refundAmount = _sessions[key].info.baseReward.testingReward * maxTrainerInOneRound;
                deadRound.status = Session.RoundStatus.Checking;
            }else revert();
        }
        else if (_sessions[key].info.status == Session.RoundStatus.Checked){
            require((!_checkOutExpirationTimeSelectCandidateAggregator(sessionId)
                    && _indexCandidateAggregator[sessionId][currentRound].length != 0)
                    || _checkOutExpirationTimeSelectCandidateAggregator(sessionId));
            if (!_checkOutExpirationTimeApplyAggregator(sessionId)){
                for (uint256 i = 0; i < MUN_CANDIDATE_AGGREGATOR; i++){
                        candidates[i] = _trainers[sessionId][currentRound][_indexCandidateAggregator[sessionId][currentRound][i]];
                }
                trainerStatusCheck = Session.TrainerStatus.Aggregating;
                refundAmount = _sessions[key].info.baseReward.testingReward * maxTrainerInOneRound;       
                deadRound.status = Session.RoundStatus.Checked;
            }else revert();
        }
        else if (_sessions[key].info.status == Session.RoundStatus.Aggregating){
            if (!_timeLock.checkExpirationTimeOfAggregatingRound(sessionId)){
                trainerStatusCheck = Session.TrainerStatus.Checked;
                refundAmount = _sessions[key].info.baseReward.aggregatingReward
                                + _sessions[key].info.baseReward.testingReward * maxTrainerInOneRound;
                deadRound.status = Session.RoundStatus.Aggregating;
            }else revert();
        }
        else if (_sessions[key].info.status == Session.RoundStatus.Testing){
            if (!_timeLock.checkExpirationTimeOfTestRound(sessionId)){
                trainerStatusCheck = Session.TrainerStatus.Done;
                refundAmount = _sessions[key].info.baseReward.testingReward * maxTrainerInOneRound;
                deadRound.status = Session.RoundStatus.Testing;
            }else revert();
        }
        uint256 totalRefundAmount = _calRefundAmount((candidates[0] != address(0) ? candidates : _trainers[sessionId][currentRound]),
                                        sessionId, currentRound, trainerStatusCheck, refundAmount);
        _deadRounds[sessionId].push(deadRound);
        unchecked {
            balanceFeTokenInSession[sessionId] += totalRefundAmount;
            _sessions[key].info.currentRound++;
            _sessions[key].info.maxRound++;
        }
        _sessions[key].info.status = Session.RoundStatus.Ready;
    }
    //FIXME: 
    function _restartRound(uint256 key, uint256 sessionId, uint256 currentRound) internal {
        // _sessions[key].deadRounds.push(currentRound);
        // unchecked {
        //     _sessions[key].info.currentRound++;
        //     _sessions[key].info.maxRound++;
        // }
        // _sessions[key].info.status = Session.RoundStatus.Ready;
    }
    function replaceRound(uint256 sessionId) external lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.owner == msg.sender);
        require(_sessions[key].info.status != Session.RoundStatus.Ready);
        require(_sessions[key].info.status != Session.RoundStatus.End);
        uint256 currentRound = _sessions[key].info.currentRound;

        _replaceRound(sessionId, key, currentRound);

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
        
        if (_trainers[sessionId][currentRound].length == 1)
        {
            _trainers[sessionId][currentRound].pop();
        }else {
            uint256 indexSender = _trainerDetails[sessionId][currentRound][msg.sender].indexInTrainerList;
            uint256 indexLastTrainer = _trainers[sessionId][currentRound].length - 1;
            address lastTrainer = _trainers[sessionId][currentRound][indexLastTrainer];
            
            delete _trainers[sessionId][currentRound][indexSender];
            _trainers[sessionId][currentRound][indexSender] = _trainers[sessionId][currentRound][indexLastTrainer];
            _trainers[sessionId][currentRound].pop();
            _trainerDetails[sessionId][currentRound][lastTrainer].indexInTrainerList = indexSender;
        }
        
        uint256 amountStake = amountStakes[msg.sender][sessionId];
        amountStakes[msg.sender][sessionId] = 0;
        unchecked {
            _numCurrentSessionJoined[msg.sender] -= 1;
        }
        payable(msg.sender).transfer(amountStake / (10**REWARD_DECIMAL));
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
        uint256 amountStake = amountStakes[trainer][sessionId] - _sessions[sessionKey].info.baseReward.trainingReward * 2;
        amountStakes[trainer][sessionId] = _sessions[sessionKey].info.baseReward.trainingReward * 2;
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
    function _refund(
        uint256 sessionId,
        uint256 key,
        Session.RoundStatus roundStatusCheck,
        bool expirationTimeCheck,
        address trainer,
        Session.TrainerStatus trainerStatusCheck,
        uint256 baseReward
    ) internal returns(uint256 amountRefund) {
        uint256 numTrainers = _sessions[key].info.maxTrainerInOneRound;
        uint256 amountStake = baseReward * numTrainers;
        amountRefund = 0;
        if (_deadRounds[sessionId].length != 0){
            for (uint i = 0; i < _deadRounds[sessionId].length; i++){
                Session.DeadRound memory deadRound = _deadRounds[sessionId][i];
                if (deadRound.status == roundStatusCheck){
                    if (_trainerDetails[sessionId][i][trainer].status == trainerStatusCheck){
                        _trainerDetails[sessionId][i][trainer].status = Session.TrainerStatus.Unavailable;
                        unchecked {
                            balanceFeTokenInSession[sessionId] -= baseReward;
                            amountRefund += (amountStake + baseReward);
                            amountStakes[trainer][sessionId] -= amountStake;
                            _numCurrentSessionJoined[trainer] -= 1;
                        }
                    }
                }
            }
        }else {
            uint256 currentRound = _sessions[key].info.currentRound;
            require(_sessions[key].info.status == roundStatusCheck);
            require(!expirationTimeCheck);
            require(_trainerDetails[sessionId][currentRound][trainer].status == trainerStatusCheck);
            
            _trainerDetails[sessionId][currentRound][trainer].status = Session.TrainerStatus.Unavailable;
            unchecked {
                balanceFeTokenInSession[sessionId] -= baseReward;
                amountRefund += (amountStake + baseReward);
                amountStakes[trainer][sessionId] -= amountStake;
                _numCurrentSessionJoined[trainer] -= 1;
            }
        }
    }
    function refundStakeCheckingRound(uint256 sessionId) external lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 amountRefund = _refund(
                                        sessionId,
                                        key,
                                        Session.RoundStatus.Training,
                                        _timeLock.checkExpirationTimeOfTrainingRound(sessionId),
                                        msg.sender,
                                        Session.TrainerStatus.Trained,
                                        _sessions[key].info.baseReward.checkingReward
                                        );
        require(amountRefund > 0);
        _feToken.mint(msg.sender, amountRefund);
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
        uint256 amountStake = amountStakes[trainer][sessionId] - _sessions[sessionKey].info.baseReward.trainingReward * 2;
        amountStakes[trainer][sessionId] = 0;
        unchecked{
            balanceFeTokenInSession[sessionId] -= reward;
        }
        _feToken.mint(trainer, reward + amountStake);
    }

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
                if (_trainerDetails[sessionId][currentRound][trainer].trainerReportedBadUpdateIdInCheckingRound.length
                == ERROR_VOTE_REPORTED){
                    unchecked {
                        _sessions[key].numberOfErrorTrainerUpdateId += 1;
                    }
                    _trainerDetails[sessionId][currentRound][trainer].status = Session.TrainerStatus.TrainingFailed;
                }
            }
        }
        unchecked {
            _sessions[key].countSubmitted += 1;
        }
        _trainerDetails[sessionId][currentRound][msg.sender].status
        = (_trainerDetails[sessionId][currentRound][msg.sender].status != Session.TrainerStatus.TrainingFailed
            ? Session.TrainerStatus.Checked : Session.TrainerStatus.TrainingFailed);
        if (_sessions[key].countSubmitted == _sessions[key].info.maxTrainerInOneRound)
        {
            uint256 margin = _sessions[key].info.maxTrainerInOneRound % 2 == 0
                                    ? _sessions[key].info.maxTrainerInOneRound / 2
                                    : _sessions[key].info.maxTrainerInOneRound / 2 + 1;
            if (_sessions[key].numberOfErrorTrainerUpdateId >= margin){
                _sessions[key].info.status = Session.RoundStatus.TrainingFailed;            
            }else{
                _sessions[key].info.status = Session.RoundStatus.Checked;
            }
            _sessions[key].countSubmitted = 0;
        }
        _receiveBaseCheckingRewardAndStakedAmount(msg.sender, key);
        amountStakes[msg.sender][sessionId] = amountStake;
    }














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
        require(_indexCandidateAggregator[sessionId][currentRound].length == 0);

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
    function _checkOutExpirationTimeSelectCandidateAggregator(uint256 sessionId) internal view returns(bool){
        (, uint256 startTimeCheckingRound, , ) = _timeLock.getStartTimeOfEachRoundInSession(sessionId);
        (, uint256 expirationTimeCheckingRound, , ) = _timeLock.getExpirationTimeOfEachRoundInSession(sessionId);
        (uint256 maxExpirationTimeOfSelectCandidateAggregator, ) = _timeLock.getExpirationTimeOfSelectCandidateAggregatorAndApply();
        return (block.timestamp - startTimeCheckingRound
                < maxExpirationTimeOfSelectCandidateAggregator + expirationTimeCheckingRound);
    }
    function submitIndexCandidateAggregator(uint256 sessionId, uint256 candidatesEncode) external override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.owner == msg.sender);
        require(_sessions[key].info.status == Session.RoundStatus.Checked);
        require(_checkOutExpirationTimeSelectCandidateAggregator(sessionId));
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_indexCandidateAggregator[sessionId][currentRound].length == 0);

        uint256[] memory candidatesDecode = _decodeCandidates(candidatesEncode, _randomFactor[sessionId]);
        require(candidatesDecode[0] == _randomFactor[sessionId]);

        _indexCandidateAggregator[sessionId][currentRound] = [
            candidatesDecode[1],
            candidatesDecode[2],
            candidatesDecode[3],
            candidatesDecode[4],
            candidatesDecode[5]
        ];
    }
    function _checkOutExpirationTimeApplyAggregator(uint256 sessionId) internal view returns(bool){
        (, uint256 startTimeCheckingRound, , ) = _timeLock.getStartTimeOfEachRoundInSession(sessionId);
        (, uint256 expirationTimeCheckingRound, , ) = _timeLock.getExpirationTimeOfEachRoundInSession(sessionId);
        (uint256 maxExpirationTimeOfSelectCandidateAggregator,
        uint256 maxExpirationTimeOfApplyAggregator) = _timeLock.getExpirationTimeOfSelectCandidateAggregatorAndApply();
        return (block.timestamp - startTimeCheckingRound
                <
                maxExpirationTimeOfSelectCandidateAggregator
                + expirationTimeCheckingRound
                + maxExpirationTimeOfApplyAggregator * MUN_CANDIDATE_AGGREGATOR);
    }
    function applyAggregator(uint256 sessionId) external payable lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Checked);
        require(_checkOpportunityAggregate(sessionId, msg.sender));
        require(_sessions[key].indexAggregator == MAX_TRAINER_IN_ROUND + 1);
        require(_checkOutExpirationTimeApplyAggregator(sessionId));
        uint256 amountStake = msg.value * (10**REWARD_DECIMAL);
        require(amountStake == _sessions[key].info.baseReward.aggregatingReward);

        uint256 currentRound = _sessions[key].info.currentRound;
        uint256 indexApplier = _trainerDetails[sessionId][currentRound][msg.sender].indexInTrainerList;
        _sessions[key].indexAggregator = indexApplier;
        _sessions[key].info.status = Session.RoundStatus.Aggregating;
        _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Aggregating;
        unchecked {
            amountStakes[msg.sender][sessionId] += amountStake;
        }
        _timeLock.setAggregatingRoundStartTime(sessionId);
    }
    function getDataDoAggregate(uint256 sessionId) external view returns(uint256[] memory) {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_sessions[key].info.status == Session.RoundStatus.Aggregating);
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Aggregating);
        require(_timeLock.checkExpirationTimeOfAggregatingRound(sessionId));
        uint256 len = _trainers[sessionId][currentRound].length;
        uint256[] memory updateModelParamIds = new uint256[](len);
        for (uint256 i = 0; i < len; i++){
            address trainer  = _trainers[sessionId][currentRound][i];
            updateModelParamIds[i] = _trainerDetails[sessionId][currentRound][trainer].updateId;
        }
        return updateModelParamIds;
    }
    function _receiveBaseaggregatingReward(address aggregator, uint256 sessionKey) internal {
        uint256 sessionId = _sessions[sessionKey].info.sessionId;
        uint256 reward = _sessions[sessionKey].info.baseReward.aggregatingReward;
        unchecked {
            balanceFeTokenInSession[sessionId] -= reward;
            amountStakes[aggregator][sessionId] -= reward;
        }
        _feToken.mint(aggregator, reward*2);
    }
 
    function submitAggregate(uint256 sessionId, uint256 updateId, uint256[] memory indexOfTrainerHasBadUpdateId) external lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_sessions[key].info.status == Session.RoundStatus.Aggregating);
        require(_timeLock.checkExpirationTimeOfAggregatingRound(sessionId));
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Aggregating);
        uint256 countErrorUpdateIdInAggregatingRound;
        uint256 numberOfErrorTrainerUpdateId = _sessions[key].numberOfErrorTrainerUpdateId;
        if (indexOfTrainerHasBadUpdateId.length >= numberOfErrorTrainerUpdateId){
            for (uint256 i = 0; i < indexOfTrainerHasBadUpdateId.length; i++){
                uint256 index = indexOfTrainerHasBadUpdateId[i];
                address trainer = _trainers[sessionId][currentRound][index];
                if(_trainerDetails[sessionId][currentRound][trainer].trainerReportedBadUpdateIdInCheckingRound.length >= ERROR_VOTE_REPORTED){
                    unchecked {
                        countErrorUpdateIdInAggregatingRound += 1;
                    }
                }
                _trainerDetails[sessionId][currentRound][trainer].aggregatorReportedBadUpdateIdInAggregateRound = true;
            }
        }
        _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Checked;
        _sessions[key].indexAggregator = MAX_TRAINER_IN_ROUND + 1;
        if (countErrorUpdateIdInAggregatingRound == numberOfErrorTrainerUpdateId){
            _sessions[key].latestGlobalModelParamId = updateId;
            _sessions[key].info.status = Session.RoundStatus.Testing;
            _receiveBaseaggregatingReward(msg.sender, key);
            _timeLock.setTestingRoundStartTime(sessionId);
        }
        else {
            _sessions[key].info.status == Session.RoundStatus.Checked;
            uint256 amountStake = _sessions[key].info.baseReward.aggregatingReward;
            unchecked {
                amountStakes[msg.sender][sessionId] -= amountStake;
            }
            _feToken.mint(msg.sender, amountStake);
        }
    }
















    function getDataDoTesting(uint256 sessionId) external view override returns(uint256, uint256[] memory){
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Testing);
        require(_timeLock.checkExpirationTimeOfTestRound(sessionId));
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Checked);
        uint256 latestGlobalModelParamId = _sessions[key].latestGlobalModelParamId;
        return (
            latestGlobalModelParamId,
            _getDataForRandom(sessionId, currentRound, Session.RoundStatus.Testing, msg.sender));
    }
    function _receiveBaseTestingReward(address trainer, uint256 sessionKey) internal {
        uint256 sessionId = _sessions[sessionKey].info.sessionId;
        uint256 reward = _sessions[sessionKey].info.baseReward.testingReward;
        uint256 amountStake = amountStakes[trainer][sessionId];
        amountStakes[trainer][sessionId] = 0;
        unchecked {
            balanceFeTokenInSession[sessionId] -= reward;
        }
        _feToken.mint(trainer, reward + amountStake);
    }
    
    function _resetRound(uint256 sessionKey) internal {
        _sessions[sessionKey].countSubmitted = 0;
        _sessions[sessionKey].numberOfErrorTrainerUpdateId = 0;
        unchecked {
            _sessions[sessionKey].info.currentRound += 1;
        }
    }
    function submitScores(uint256 sessionId, bool[] memory scores) external lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        require(_sessions[key].info.status == Session.RoundStatus.Testing);
        require(_timeLock.checkExpirationTimeOfTestRound(sessionId));
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Checked);

        uint256[] memory indexOfTrainerListSelectedForTesting = _getIndexTrainerSelectedForRandom(sessionId, currentRound, msg.sender, Session.RoundStatus.Testing);
        for(uint256 i = 0; i < indexOfTrainerListSelectedForTesting.length; i++){            
            address trainerSelected = _trainers[sessionId][currentRound][indexOfTrainerListSelectedForTesting[i]];
            if (scores[i]){
                unchecked {
                    countScores[sessionId][currentRound][_trainerDetails[sessionId][currentRound][trainerSelected].scores] -= 1;
                    _trainerDetails[sessionId][currentRound][trainerSelected].scores += 1;
                    countScores[sessionId][currentRound][_trainerDetails[sessionId][currentRound][trainerSelected].scores] += 1;
                }
            }
        }
        unchecked {
            _sessions[key].countSubmitted += 1;
            _numCurrentSessionJoined[msg.sender] -= 1;
        }
        _trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Done;

        if (_sessions[key].countSubmitted == _sessions[key].info.maxTrainerInOneRound)
        {
            _resetRound(key);
            if (_sessions[key].info.currentRound == _sessions[key].info.maxRound){
                _sessions[key].info.status = Session.RoundStatus.End;
            }
            else {
                _sessions[key].info.status = Session.RoundStatus.Ready;
            }
        }
        _receiveBaseTestingReward(msg.sender, key);
    }

    function refundStakeTestingRoundWhenCurrentRoundIsChecking(uint256 sessionId) external lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 amountRefund = _refund(sessionId,
                                        key,
                                        Session.RoundStatus.Checking,
                                        _timeLock.checkExpirationTimeOfCheckingRound(sessionId),
                                        msg.sender,
                                        Session.TrainerStatus.Checked,
                                        _sessions[key].info.baseReward.testingReward
                                        );
        require(amountRefund > 0);
        _feToken.mint(msg.sender, amountRefund);
    }
    function refundStakeTestingRoundWhenCurrentRoundIsChecked(uint256 sessionId) external lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_sessions[key].info.status == Session.RoundStatus.Checked);
        require(_trainerDetails[sessionId][currentRound][msg.sender].status == Session.TrainerStatus.Checked);
        require((!_checkOutExpirationTimeSelectCandidateAggregator(sessionId)
                && _indexCandidateAggregator[sessionId][currentRound].length == 0)
                || (_indexCandidateAggregator[sessionId][currentRound].length != 0
                && !_checkOutExpirationTimeApplyAggregator(sessionId)
                && !_checkOpportunityAggregate(sessionId, msg.sender)));
            
        _trainerDetails[sessionId][currentRound][msg.sender].status = Session.TrainerStatus.Unavailable;
        uint256 numTrainers = _sessions[key].info.maxTrainerInOneRound;
        uint256 baseReward = _sessions[key].info.baseReward.testingReward;
        uint256 amountStake = baseReward * numTrainers;
        uint256 amountRefund = 0;
        unchecked {
            balanceFeTokenInSession[sessionId] -= baseReward;
            amountRefund += (amountStake + baseReward);
            amountStakes[msg.sender][sessionId] -= amountStake;
            _numCurrentSessionJoined[msg.sender] -= 1;
        }
        _feToken.mint(msg.sender, amountRefund);
    }
    function refundStakeTestingRoundWhenCurrentRoundIsAggregating(uint256 sessionId) external override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 amountRefund = _refund(sessionId,
                                        key,
                                        Session.RoundStatus.Aggregating,
                                        _timeLock.checkExpirationTimeOfAggregatingRound(sessionId),
                                        msg.sender,
                                        Session.TrainerStatus.Checked,
                                        _sessions[key].info.baseReward.testingReward
                                        );
        require(amountRefund > 0);
        _feToken.mint(msg.sender, amountRefund);
    }
    
    function claimPerformanceReward(uint256 sessionId, uint256 round) external lock override {
        uint256 key = _keyOfSessionDetailBySessionId[sessionId];
        uint256 currentRound = _sessions[key].info.currentRound;
        require(_trainerDetails[sessionId][round][msg.sender].status ==  Session.TrainerStatus.Done);
        require((currentRound > round|| _sessions[key].info.status == Session.RoundStatus.End)
                || (currentRound == round && !_timeLock.checkExpirationTimeOfTestRound(sessionId)));
        require(!_performanceRewardDistribution.isClaim(msg.sender, sessionId, round));
        uint256 score = _trainerDetails[sessionId][round][msg.sender].scores;
        require(score > 0);
        uint256 amountSendToTrainer = _performanceRewardDistribution.claim(
                                            msg.sender,
                                            sessionId,
                                            round,
                                            score,
                                            _sessions[key].info.performanceReward,
                                            _sessions[key].info.maxTrainerInOneRound
                                            );
        unchecked {
            balanceFeTokenInSession[sessionId] -= amountSendToTrainer;
        }
    }
    /**
     * 
     * 
     * 
     */
















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