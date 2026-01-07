// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILendlePool} from "../interfaces/ILendlePool.sol";
import {MockAToken} from "./MockAToken.sol";

/// @title MockLendlePool
/// @notice Mock implementation of Lendle Pool for local testing
/// @dev Simulates supply, withdraw, and yield generation
contract MockLendlePool is ILendlePool {
    using SafeERC20 for IERC20;

    struct Reserve {
        address aTokenAddress;
        uint128 liquidityRate;
        uint128 variableBorrowRate;
        uint40 lastUpdateTimestamp;
        bool isActive;
    }

    mapping(address => Reserve) public reserves;

    event Supply(
        address indexed asset,
        address indexed user,
        address indexed onBehalfOf,
        uint256 amount,
        uint16 referralCode
    );

    event Withdraw(
        address indexed asset,
        address indexed user,
        address indexed to,
        uint256 amount
    );

    /// @notice Initialize a reserve with its aToken
    /// @param asset The underlying asset address
    /// @param aToken The aToken address
    /// @param liquidityRate The initial supply APY (in ray, e.g., 0.1e27 = 10%)
    function initReserve(address asset, address aToken, uint128 liquidityRate) external {
        reserves[asset] = Reserve({
            aTokenAddress: aToken,
            liquidityRate: liquidityRate,
            variableBorrowRate: 0,
            lastUpdateTimestamp: uint40(block.timestamp),
            isActive: true
        });
    }

    /// @notice Supply assets to the pool
    /// @param asset The address of the underlying asset to supply
    /// @param amount The amount to supply
    /// @param onBehalfOf The address that will receive the aTokens
    /// @param referralCode Code used for referral tracking (unused in mock)
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external override {
        Reserve memory reserve = reserves[asset];
        require(reserve.isActive, "Reserve not active");

        // Transfer underlying asset from user to aToken contract
        IERC20(asset).safeTransferFrom(msg.sender, reserve.aTokenAddress, amount);

        // Mint aTokens to user
        MockAToken(reserve.aTokenAddress).mint(onBehalfOf, amount);

        emit Supply(asset, msg.sender, onBehalfOf, amount, referralCode);
    }

    /// @notice Withdraw assets from the pool
    /// @param asset The address of the underlying asset to withdraw
    /// @param amount The amount to withdraw (use type(uint256).max for max)
    /// @param to The address that will receive the underlying assets
    /// @return The final amount withdrawn
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override returns (uint256) {
        Reserve memory reserve = reserves[asset];
        require(reserve.isActive, "Reserve not active");

        MockAToken aToken = MockAToken(reserve.aTokenAddress);

        // If amount is max uint, withdraw full balance
        uint256 userBalance = aToken.balanceOf(msg.sender);
        uint256 amountToWithdraw = amount == type(uint256).max ? userBalance : amount;

        require(amountToWithdraw <= userBalance, "Insufficient aToken balance");

        // Check available liquidity
        uint256 availableLiquidity = IERC20(asset).balanceOf(reserve.aTokenAddress);
        require(amountToWithdraw <= availableLiquidity, "Insufficient liquidity");

        // Burn aTokens from user
        aToken.burn(msg.sender, amountToWithdraw);

        // Transfer underlying asset to user
        IERC20(asset).safeTransferFrom(reserve.aTokenAddress, to, amountToWithdraw);

        emit Withdraw(asset, msg.sender, to, amountToWithdraw);

        return amountToWithdraw;
    }

    /// @notice Get reserve data (simplified for mock)
    /// @param asset The address of the underlying asset
    /// @return data ReserveData struct with aToken address and rates
    function getReserveData(address asset)
        external
        view
        override
        returns (ReserveData memory data)
    {
        Reserve memory reserve = reserves[asset];
        
        data.configuration = 0;
        data.liquidityIndex = uint128(1e27);
        data.currentLiquidityRate = reserve.liquidityRate;
        data.variableBorrowRate = reserve.variableBorrowRate;
        data.stableBorrowRate = 0;
        data.lastUpdateTimestamp = reserve.lastUpdateTimestamp;
        data.id = 0;
        data.aTokenAddress = reserve.aTokenAddress;
        data.stableDebtTokenAddress = address(0);
        data.variableDebtTokenAddress = address(0);
        data.interestRateStrategyAddress = address(0);
        data.treasury = address(0);
        data.incentivesController = address(0);
    }

    /// @notice Get available liquidity for an asset
    /// @param asset The address of the underlying asset
    /// @return Available liquidity in the pool
    function getAvailableLiquidity(address asset) external view returns (uint256) {
        Reserve memory reserve = reserves[asset];
        if (!reserve.isActive) return 0;
        return IERC20(asset).balanceOf(reserve.aTokenAddress);
    }

    /// @notice Advance time to simulate yield accrual (for testing)
    /// @param asset The address of the underlying asset
    function simulateYieldAccrual(address asset) external {
        Reserve memory reserve = reserves[asset];
        require(reserve.isActive, "Reserve not active");
        
        MockAToken(reserve.aTokenAddress).updateIndex();
    }
}
