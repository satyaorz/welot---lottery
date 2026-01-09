// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IEntropyV2, IEntropyConsumer} from "../interfaces/IEntropyV2.sol";

/// @notice Minimal mock of Pyth Entropy V2 request flow.
contract MockEntropyV2 is IEntropyV2 {
    uint256 public fee;
    uint64 public nextSeq;

    error MockEntropyV2__NoRequest();

    mapping(uint64 => address) public requester;

    constructor() {
        fee = 0; // Free for local testing
        nextSeq = 1;
    }

    function setFee(uint256 fee_) external {
        fee = fee_;
    }

    function getFee(address) external view override returns (uint256) {
        return fee;
    }

    function getFeeV2() external view override returns (uint256) {
        return fee;
    }

    function requestV2() external payable override returns (uint64 sequenceNumber) {
        sequenceNumber = nextSeq++;
        requester[sequenceNumber] = msg.sender;
    }

    /// @notice Simulate fulfillment (call this from tests)
    function fulfill(uint64 sequenceNumber, bytes32 random) external {
        address target = requester[sequenceNumber];
        if (target == address(0)) revert MockEntropyV2__NoRequest();
        IEntropyConsumer(target).entropyCallback(sequenceNumber, address(this), random);
    }

    /// @notice Direct fulfillment with target address
    function fulfillRandomness(address target, uint256 sequenceNumber, bytes32 random) external {
        IEntropyConsumer(target).entropyCallback(uint64(sequenceNumber), address(this), random);
    }
}
