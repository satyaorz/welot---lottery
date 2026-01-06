// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {MockERC20} from "./MockERC20.sol";

/// @title MockERC4626
/// @notice Yield-generating vault mock for testing.
///         In local/dev, this auto-accrues yield over time so prize pools can grow without
///         needing someone to donate tokens.
contract MockERC4626 is ERC4626 {
    using Math for uint256;

    uint8 private immutable _decimals;

    /// @notice Simulated yield rate (in underlying asset units per second)
    uint256 public yieldRatePerSecond;
    /// @notice Last timestamp when yield was realized (minted) into the vault
    uint64 public lastYieldTimestamp;

    constructor(
        MockERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC4626(IERC20(asset_)) ERC20(name_, symbol_) {
        _decimals = decimals_;

        // Default: ~1 token/hour of auto-yield (scaled by token decimals).
        // This is only for local testing and demos.
        yieldRatePerSecond = (10 ** uint256(decimals_)) / 3600;
        lastYieldTimestamp = uint64(block.timestamp);
    }

    function decimals() public view override(ERC4626) returns (uint8) {
        return _decimals;
    }

    /// @notice Configure the auto-yield rate (local testing only)
    function setYieldRatePerSecond(uint256 newRate) external {
        // Realize any pending yield before changing the rate.
        _realizeYield();
        yieldRatePerSecond = newRate;
    }

    function _pendingYield() internal view returns (uint256) {
        if (yieldRatePerSecond == 0) return 0;
        uint256 dt = block.timestamp - uint256(lastYieldTimestamp);
        return dt * yieldRatePerSecond;
    }

    function _realizeYield() internal {
        uint256 pending = _pendingYield();
        if (pending > 0) {
            MockERC20(asset()).mint(address(this), pending);
        }
        lastYieldTimestamp = uint64(block.timestamp);
    }

    /// @dev Report assets including simulated (unrealized) yield.
    ///      The yield is minted lazily on deposits/withdrawals so transfers always succeed.
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this)) + _pendingYield();
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _realizeYield();
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        _realizeYield();
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @notice Donate yield to the vault (simulates interest accrual)
    /// @dev Mints underlying tokens directly into the vault, increasing share value
    function donateYield(uint256 assets) external {
        MockERC20(asset()).transferFrom(msg.sender, address(this), assets);
    }

    /// @notice Simulate yield by minting new tokens directly (no transfer needed)
    function simulateYield(uint256 assets) external {
        MockERC20(asset()).mint(address(this), assets);
    }
}
