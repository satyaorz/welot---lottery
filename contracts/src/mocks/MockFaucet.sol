// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {MockERC20} from "./MockERC20.sol";

/// @title MockFaucet
/// @notice Multi-token faucet for testing. Allows claiming test tokens.
/// @dev Each user can claim each token once every `cooldown` seconds
contract MockFaucet {
    /// @notice Amount to give per token type
    uint256 public constant CLAIM_AMOUNT_18 = 1000e18;  // For 18 decimal tokens
    uint256 public constant CLAIM_AMOUNT_6 = 1000e6;    // For 6 decimal tokens

    /// @notice Cooldown between claims (0 = one-time claim)
    uint256 public cooldown;

    /// @notice Registered tokens that can be claimed
    address[] public tokens;
    mapping(address => bool) public isToken;

    /// @notice Last claim time per user per token
    mapping(address => mapping(address => uint256)) public lastClaim;

    /// @notice Owner for admin functions
    address public owner;

    error NotOwner();
    error TokenNotRegistered();
    error ClaimCooldown();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(uint256 cooldown_) {
        owner = msg.sender;
        cooldown = cooldown_;
    }

    /// @notice Register a token for faucet claims
    function addToken(address token) external onlyOwner {
        if (!isToken[token]) {
            isToken[token] = true;
            tokens.push(token);
        }
    }

    /// @notice Remove a token from faucet
    function removeToken(address token) external onlyOwner {
        isToken[token] = false;
        // Note: doesn't remove from array, just disables
    }

    /// @notice Claim tokens
    /// @param token The token address to claim
    function claim(address token) external {
        if (!isToken[token]) revert TokenNotRegistered();
        
        if (cooldown > 0) {
            if (block.timestamp < lastClaim[msg.sender][token] + cooldown) {
                revert ClaimCooldown();
            }
        } else {
            // One-time claim
            if (lastClaim[msg.sender][token] > 0) revert ClaimCooldown();
        }

        lastClaim[msg.sender][token] = block.timestamp;

        // Determine amount based on decimals
        uint8 decimals = MockERC20(token).decimals();
        uint256 amount = decimals == 6 ? CLAIM_AMOUNT_6 : CLAIM_AMOUNT_18;

        MockERC20(token).mint(msg.sender, amount);
    }

    /// @notice Claim all available tokens at once
    function claimAll() external {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (!isToken[token]) continue;
            
            // Check cooldown
            bool eligible = cooldown > 0
                ? block.timestamp >= lastClaim[msg.sender][token] + cooldown
                : lastClaim[msg.sender][token] == 0;
            
            if (eligible) {
                lastClaim[msg.sender][token] = block.timestamp;
                uint8 decimals = MockERC20(token).decimals();
                uint256 amount = decimals == 6 ? CLAIM_AMOUNT_6 : CLAIM_AMOUNT_18;
                MockERC20(token).mint(msg.sender, amount);
            }
        }
    }

    /// @notice Check if user can claim a specific token
    function canClaim(address user, address token) external view returns (bool) {
        if (!isToken[token]) return false;
        if (cooldown > 0) {
            return block.timestamp >= lastClaim[user][token] + cooldown;
        }
        return lastClaim[user][token] == 0;
    }

    /// @notice Get list of all registered tokens
    function getTokens() external view returns (address[] memory) {
        return tokens;
    }

    /// @notice Get number of registered tokens
    function tokenCount() external view returns (uint256) {
        return tokens.length;
    }
}
