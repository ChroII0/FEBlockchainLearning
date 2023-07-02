// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

library Session {
    enum TrainerStatus {
        Unavailable,
        Training,
        TrainingFailed,
        Trained,
        Checked,
        Aggregating,
        Done
    }
    struct TrainerDetail {
        uint256 updateId;
        uint256 indexInTrainerList;
        address[] trainerReportedBadUpdateIdInCheckingRound;
        bool aggregatorReportedBadUpdateIdInAggregateRound;
        TrainerStatus status;
        uint256 scores;
    }
    enum RoundStatus {
        Ready,
        Training,
        TrainingFailed,
        Checking,
        Checked,
        Aggregating,
        Testing,
        End
    }
    struct BaseReward {
        uint256 trainingReward;
        uint256 checkingReward;
        uint256 aggregatingReward;
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
    struct DeadRound {
        uint256 round;
        RoundStatus status;
    }
    struct Detail {
        Info info;
        uint256 globalModelId;
        uint256 latestGlobalModelParamId;
        uint256 indexAggregator;
        uint256 countSubmitted;
        uint256 numberOfErrorTrainerUpdateId;
    }
}
