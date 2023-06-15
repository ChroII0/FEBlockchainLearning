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
    struct TesterStatus {
        address trainerSelected;
        bool isTester;
    }
    // enum SessionStatus {
    //     Ready,
    //     End
    // }
    enum RoundStatus {
        Unavailable,
        Training,
        Scoring,
        Scored,
        Aggregating,
        End
    }
    enum TrainerStatus {
        Unavailable,
        Training,
        Trained,
        Testing,
        Tested
    }
    struct BaseReward {
        uint256 trainingReward;
        uint256 testingReward;
        uint256 aggregateReward;
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
        address[] trainers;
        address aggreator;
        uint256 numberOfTrainingSubmitted;
        uint256 numberOfTestingSubmitted;
        uint256 numberTrainerNotYetSelectedForTesting;
        // mapping(address => bool) selectedForTesting;
    }
}
