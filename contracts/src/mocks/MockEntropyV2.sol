// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IEntropyV2} from "../interfaces/IEntropyV2.sol";

/// @notice Minimal mock of Pyth Entropy V2 request flow for localhost.
contract MockEntropyV2 is IEntropyV2 {
    uint256 public fee;
    uint64 public nextSeq;

    mapping(uint64 => address) public requester;

    constructor(uint256 fee_) {
        fee = fee_;
        nextSeq = 1;
    }

    function setFee(uint256 fee_) external {
        fee = fee_;
    }

    function getFeeV2() external view returns (uint256) {
        return fee;
    }

    function requestV2() external payable returns (uint64 sequenceNumber) {
        require(msg.value == fee, "FEE");
        sequenceNumber = nextSeq++;
        requester[sequenceNumber] = msg.sender;
    }

    function fulfill(uint64 sequenceNumber, bytes32 random) external {
        address target = requester[sequenceNumber];
        require(target != address(0), "NO_REQ");
        (bool ok,) = target.call(
            abi.encodeWithSignature(
                "entropyCallback(uint64,address,bytes32)",
                sequenceNumber,
                address(this),
                random
            )
        );
        require(ok, "CALLBACK_FAIL");
    }
}
