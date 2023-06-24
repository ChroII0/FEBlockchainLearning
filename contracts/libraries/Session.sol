// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

library Session {
    struct scoreObject {
        uint256 accuracy;
        uint256 loss;
        uint256 precision;
        uint256 recall;
        uint256 f1;
    }
    enum TrainerStatus {
        Unavailable,
        Training,
        TrainedFailed,
        Trained,
        Checking,
        Checked,
        Testing,
        Tested,
        TestedFailed,
        TrainedAndTestedFailed,
        Aggregating,
        Aggregated,
        AggregatedFailed
    }
    struct TrainerDetail {
        uint256 updateId;
        uint256 indexInTrainerList;
        address[] trainerReportedBadUpdateIdInCheckingRound;
        address[] trainerReportedBadUpdateIdInTestingRound;
        bool aggregatorReportedBadUpdateIdInAggregateRound;
        TrainerStatus status;
        scoreObject scores;
    }
    // struct TesterStatus {
    //     address trainerSelected;
    //     bool isTester;
    // }
    // enum SessionStatus {
    //     Ready,
    //     End
    // }
    enum RoundStatus {
        Ready,
        Training,
        Checking,
        Checked,
        Aggregating,
        Testing,
        End
    }
    struct BaseReward {
        uint256 trainingReward;
        uint256 checkingReward;
        uint256 aggregateReward;
        uint256 testingReward;
    }
    struct Info {
        uint256 sessionId;
        address owner;
        uint256 performanceReward;
        BaseReward baseReward;
        uint256 maxRound;
        uint256 currentRound;
        uint256 maxTrainerInOneRound;
        RoundStatus status;
    }
    struct Detail {
        Info info;
        uint256 globalModelId;
        uint256 latestGlobalModelParamId;
        address aggregator;
        uint256 countSubmitted;
        uint256 numberOfErrorTrainerUpdateId;
        // uint256 numberTrainerNotYetSelectedForTesting;
        // mapping(address => bool) selectedForTesting;
    }
}
