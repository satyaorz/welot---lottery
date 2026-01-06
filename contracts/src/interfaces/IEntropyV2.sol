// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @title IEntropyV2
/// @notice Interface for Pyth Entropy V2 (randomness provider)
/// @dev Pyth Entropy provides verifiable randomness on Mantle and other networks
interface IEntropyV2 {
    /// @notice Get the fee required for requesting randomness (legacy)
    /// @param provider The entropy provider address
    function getFee(address provider) external view returns (uint256);

    /// @notice Get the fee required for requesting randomness (V2)
    function getFeeV2() external view returns (uint256);

    /// @notice Request a random number
    /// @return sequenceNumber The unique identifier for this request
    function requestV2() external payable returns (uint64 sequenceNumber);
}

/// @title IEntropyConsumer
/// @notice Interface that consumers must implement to receive randomness callbacks
interface IEntropyConsumer {
    /// @notice Callback function called by Entropy when randomness is ready
    /// @param sequenceNumber The sequence number of the request
    /// @param provider The address of the entropy provider
    /// @param randomNumber The random number
    function entropyCallback(uint64 sequenceNumber, address provider, bytes32 randomNumber) external;
}
