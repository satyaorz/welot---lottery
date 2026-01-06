// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title IYieldSource
/// @notice Generic interface for yield sources
/// @dev Abstracts different yield strategies (ERC4626, mETH staking, etc.)
interface IYieldSource {
    /// @notice The underlying asset of this yield source
    function asset() external view returns (address);

    /// @notice Deposit assets into the yield source
    /// @param assets Amount of assets to deposit
    /// @return shares Amount of shares received
    function deposit(uint256 assets) external returns (uint256 shares);

    /// @notice Withdraw assets from the yield source
    /// @param assets Amount of assets to withdraw
    /// @return shares Amount of shares burned
    function withdraw(uint256 assets) external returns (uint256 shares);

    /// @notice Get the total assets controlled by this yield source
    function totalAssets() external view returns (uint256);

    /// @notice Get the total shares outstanding
    function totalShares() external view returns (uint256);

    /// @notice Convert assets to shares
    function convertToShares(uint256 assets) external view returns (uint256);

    /// @notice Convert shares to assets
    function convertToAssets(uint256 shares) external view returns (uint256);
}
