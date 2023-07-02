// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/IPerformanceRewardDistribution.sol";
import "./interfaces/IAdminControlMetadata.sol";
import "./interfaces/IFEToken.sol";
import "./interfaces/IFEBlockchainLearning.sol";


abstract contract FEBlockchainLearning is IFEBlockchainLearning {
    function MIN_TRAINER_IN_ROUND() public view virtual returns(uint256);
    function countScores(uint256 sessionId, uint256 round) public view virtual returns(uint256[] memory);
}

contract PerformanceRewardDistribution is IPerformanceRewardDistribution{
    
    struct Ratio {
        uint256 numerator;
        uint256 denominator;
    }
    Ratio public K = Ratio(1,1);
    // trainer => sessionId => round[]
    mapping (address => mapping (uint256 => uint256[])) private _completedRounds;
    // trainer => sessionId => round => bool
    mapping (address => mapping (uint256 => mapping (uint256 => bool))) public isClaimed;


    IAdminControlMetadata private _adminControl;
    IFEToken private _feToken;
    constructor(address adminControl, address feToken) {
        _adminControl = IAdminControlMetadata(adminControl);
        _feToken = IFEToken(feToken);
    }
    modifier onlyAdmin(address account) {
        require(_adminControl.isAdmin(account) == true, "You are not admin");
        _;
    }
    modifier onlyCaller(address account) {
        require(_adminControl.isCallerPerformanceRewardDistribution(account) == true, "You are not allow caller");
        _;
    }

    function setK(uint256 kx, uint256 ky) external onlyAdmin(msg.sender) override {
        require(kx > 0 && kx <= 100);
        require(ky > 0 && ky <= 100);
        K.numerator = kx;
        K.denominator = ky;
    }


    function getCompletedRound(address trainer, uint256 sessionId)
    external view override returns(uint256[] memory rounds, bool[] memory isClaimeds)  {
        
        uint256 lens = _completedRounds[trainer][sessionId].length;
        isClaimeds = new bool[](lens);
        rounds = _completedRounds[trainer][sessionId];
        for (uint256 i = 0; i < lens; i++){
            isClaimeds[i] = isClaimed[trainer][sessionId][_completedRounds[trainer][sessionId][i]];
        }
    }        
    


    function completeRoundOfSession(address trainer, uint256 sessionId, uint256 currentRound) external onlyCaller(msg.sender) override {
        _completedRounds[trainer][sessionId].push(currentRound);
    }

    function _Sn(uint256 n) internal pure returns(uint256){
        return n*(1+n)/2;
    }
    
    function calAmountReward(
            uint256 score,
            uint256 PR,
            uint256 TrS,
            uint256 TrMin,
            uint256[] memory scores
        ) public view returns(Ratio memory) {
        
            Ratio memory P;
            Ratio memory k = K;
            if (scores[0] == TrS){
                return P;
            }
            uint256 Sscores = _Sn(TrMin - 1);
            uint256 maxScore = TrMin - 1;
            Ratio memory PRAvg;
            PRAvg.numerator = PR;
            PRAvg.denominator = TrS - scores[0];

            Ratio memory PPointAvg;
            PPointAvg.numerator = PRAvg.numerator;
            PPointAvg.denominator = PRAvg.denominator * Sscores;

            Ratio memory PRScore;
            PRScore.numerator = PRAvg.numerator;
            PRScore.denominator = PRAvg.denominator * (maxScore +  _Sn(TrMin - 2));

            (k.numerator, k.denominator) = (k.numerator * PRAvg.numerator * PRScore.denominator
                                            >= k.denominator * PRAvg.denominator * PRScore.numerator * maxScore
                                            ? (k.numerator, k.denominator)
                                            : (PRAvg.denominator * PRScore.numerator * maxScore, PRAvg.numerator * PRScore.denominator));
            P.numerator = (PRAvg.denominator ** 2) * PRScore.numerator * k.denominator * score;
            P.denominator = (PRAvg.denominator ** 2) * PRScore.denominator * k.numerator;
            for (uint i = 1; i < scores.length; i++){
                unchecked {
                    P.numerator += (scores[i]
                                * (PRAvg.numerator * PRScore.denominator * k.numerator
                                - PRAvg.denominator * PRScore.numerator * k.denominator * i));
                }
            }
            return P;
        
    }
    function claim(
        address trainer,
        uint256 sessionId, 
        uint256 round,
        uint256 score, 
        uint256 performanceRound, 
        uint256 maxTrainer
        )external onlyCaller(msg.sender) override returns(uint256) {
        uint256[] memory scores = FEBlockchainLearning(msg.sender).countScores(sessionId, round);
        uint256 TrMin = FEBlockchainLearning(msg.sender).MIN_TRAINER_IN_ROUND();
        Ratio memory p = calAmountReward(score, performanceRound, maxTrainer, TrMin, scores);
        require(p.numerator > 0 && p.numerator >= p.denominator);
        uint256 amountSendToTrainer = p.numerator / p.denominator;
        _feToken.mint(trainer, amountSendToTrainer);

        isClaimed[trainer][sessionId][round] = true;
        return amountSendToTrainer;
    }
}