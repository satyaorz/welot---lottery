// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title ILendlePool
/// @notice Interface for Lendle's main lending pool (Aave V3-based)
/// @dev Lendle is a fork of Aave V3 on Mantle Network
interface ILendlePool {
    /// @notice Supply assets to the pool and receive interest-bearing aTokens
    /// @param asset The address of the underlying asset to supply
    /// @param amount The amount of asset to supply
    /// @param onBehalfOf The address that will receive the aTokens (can be msg.sender)
    /// @param referralCode Code used for referral tracking (usually 0)
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /// @notice Withdraw assets from the pool by burning aTokens
    /// @param asset The address of the underlying asset to withdraw
    /// @param amount The amount to withdraw (use type(uint256).max to withdraw full balance)
    /// @param to The address that will receive the withdrawn assets
    /// @return The actual amount withdrawn
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);

    /// @notice Get reserve data for a given asset
    /// @param asset The address of the underlying asset
    /// @return data ReserveData struct with reserve configuration
    function getReserveData(address asset)
        external
        view
        returns (ReserveData memory data);

    /// @dev Struct representing the reserve data (simplified for our use)
    struct ReserveData {
        // Configuration bitmap
        uint256 configuration;
        // Liquidity index (used for interest calculation)
        uint128 liquidityIndex;
        // Current supply rate
        uint128 currentLiquidityRate;
        // Variable borrow rate
        uint128 variableBorrowRate;
        // Stable borrow rate
        uint128 stableBorrowRate;
        // Last update timestamp
        uint40 lastUpdateTimestamp;
        // Id of the reserve
        uint16 id;
        // aToken address (interest-bearing token)
        address aTokenAddress;
        // Stable debt token address
        address stableDebtTokenAddress;
        // Variable debt token address
        address variableDebtTokenAddress;
        // Interest rate strategy address
        address interestRateStrategyAddress;
        // Treasury address
        address treasury;
        // Incentives controller
        address incentivesController;
    }
}
