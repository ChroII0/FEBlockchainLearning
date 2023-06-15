// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface ITrainerManagement {
    // function isBlocked(address trainer) external view returns (bool);

    function isAllowed(address trainer) external view returns (bool);
}