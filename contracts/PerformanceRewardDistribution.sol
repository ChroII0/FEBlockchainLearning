// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/IPerformanceRewardDistribution.sol";
import "./interfaces/IAdminControlMetadata.sol";
import "./interfaces/IFEToken.sol";

contract PerformanceRewardDistribution is IPerformanceRewardDistribution{
    
    // trainer => sessionId => round[]
    mapping (address => mapping (uint256 => uint256[])) private _completedRounds;
    // trainer => round => bool
    mapping (address => mapping (uint256 => bool)) private _isClaimed;

    IAdminControlMetadata private _adminControl;
    IFEToken private _feToken;
    constructor(address adminControl, address feToken) {
        _adminControl = IAdminControlMetadata(adminControl);
        _feToken = IFEToken(feToken);
    }
    modifier onlyCaller(address account) {
        require(_adminControl.isCallerPerformanceRewardDistribution(account) == true, "You are not allow caller");
        _;
    }


    function getCompletedRound(address trainer, uint256 sessionId)
    external view override returns(uint256[] memory rounds, bool[] memory isClaimeds)  {
        
        uint256 lens = _completedRounds[trainer][sessionId].length;
        isClaimeds = new bool[](lens);
        rounds = _completedRounds[trainer][sessionId];
        for (uint256 i = 0; i < lens; i++){
            isClaimeds[i] = _isClaimed[trainer][_completedRounds[trainer][sessionId][i]];
        }
    }        
    


    function completeRoundOfSession(address trainer, uint256 sessionId, uint256 currentRound) external onlyCaller(msg.sender) override {
        _completedRounds[trainer][sessionId].push(currentRound);
    }



    function _claimReward(address trainer, uint256 sessionId, uint256 round) internal {

    }
    function claim(address trainer, uint256 sessionId) external onlyCaller(msg.sender) override {
        uint256 lens = _completedRounds[trainer][sessionId].length;
        for (uint256 i = 0; i < lens; i++){
            if (!_isClaimed[trainer][_completedRounds[trainer][sessionId][i]])
            {
                _claimReward(trainer, sessionId, _completedRounds[trainer][sessionId][i]);
                _isClaimed[trainer][_completedRounds[trainer][sessionId][i]] = true;
            }
        }
    }
}