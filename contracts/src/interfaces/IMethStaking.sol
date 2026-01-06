// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title IMethStaking
/// @notice Interface for mETH staking on Mantle
/// @dev mETH is Mantle's liquid staking token that earns ~1.5% APY
interface IMethStaking {
    /// @notice Stake ETH and receive mETH
    function stake() external payable returns (uint256 mETHAmount);

    /// @notice Request to unstake mETH
    /// @param mETHAmount Amount of mETH to unstake
    /// @return requestId The ID of the unstake request
    function unstakeRequest(uint256 mETHAmount) external returns (uint256 requestId);

    /// @notice Claim unstaked ETH
    /// @param requestId The ID of the unstake request
    function claimUnstakeRequest(uint256 requestId) external;

    /// @notice Get the current mETH to ETH exchange rate
    /// @return The exchange rate (1e18 = 1:1)
    function ethToMethRate() external view returns (uint256);

    /// @notice Get the mETH token address
    function mETH() external view returns (address);
}

/// @title IMETH
/// @notice Interface for the mETH token
interface IMETH {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
