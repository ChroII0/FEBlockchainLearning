// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "../libraries/Session.sol";

interface IFEBlockchainLearingMetadata {
    function allSession() external view returns(Session.Info[] memory);
    function sessionById(uint256 sessionId) external view returns(Session.Info memory);
    function getOtherTrainerDoTest(uint256 sessionId) external view returns(address, uint256);
    function checkOpportunityAggregate(uint256 sessionId) external view returns(bool);
}