// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IEntropyV2 {
    function getFeeV2() external view returns (uint256 fee);

    function requestV2() external payable returns (uint64 sequenceNumber);
}
