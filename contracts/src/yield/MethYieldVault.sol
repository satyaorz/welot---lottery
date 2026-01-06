// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MethYieldVault
/// @notice ERC4626 wrapper around mETH staking for integration with WelotVault
/// @dev This allows mETH to be used as a yield source in the lottery
/// @dev On Mantle, mETH earns ~1.5% APY through staking rewards
contract MethYieldVault is ERC4626 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // mETH staking contract on Mantle
    // Mainnet: 0x... (to be filled in)
    address public immutable stakingContract;

    // Mapping to track each depositor's mETH share
    uint256 public totalMethDeposited;

    constructor(
        IERC20 meth_,
        address stakingContract_,
        string memory name_,
        string memory symbol_
    ) ERC4626(meth_) ERC20(name_, symbol_) {
        stakingContract = stakingContract_;
    }

    /// @notice Returns total mETH held by this vault (including accrued rewards)
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Deposit mETH into the vault
    /// @dev mETH automatically accrues value through the exchange rate
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);
        totalMethDeposited += assets;
        emit Deposit(caller, receiver, assets, shares);
    }

    /// @notice Withdraw mETH from the vault
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);
        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
