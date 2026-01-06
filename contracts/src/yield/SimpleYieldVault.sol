// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SimpleYieldVault
/// @notice Simple ERC4626 vault that wraps another ERC4626 or yield source
/// @dev Use this for tokens that already have ERC4626 vaults (like sUSDe)
contract SimpleYieldVault is ERC4626 {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlyingVault;
    bool public immutable isERC4626;

    constructor(
        IERC20 asset_,
        IERC20 underlyingVault_,
        bool isERC4626_,
        string memory name_,
        string memory symbol_
    ) ERC4626(asset_) ERC20(name_, symbol_) {
        underlyingVault = underlyingVault_;
        isERC4626 = isERC4626_;
        
        // Approve underlying vault
        if (isERC4626_) {
            asset_.approve(address(underlyingVault_), type(uint256).max);
        }
    }

    function totalAssets() public view override returns (uint256) {
        if (isERC4626) {
            uint256 shares = underlyingVault.balanceOf(address(this));
            // Get assets from ERC4626
            (bool success, bytes memory data) = address(underlyingVault).staticcall(
                abi.encodeWithSignature("convertToAssets(uint256)", shares)
            );
            if (success && data.length == 32) {
                return abi.decode(data, (uint256));
            }
        }
        return IERC20(asset()).balanceOf(address(this));
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        IERC20(asset()).safeTransferFrom(caller, address(this), assets);
        
        if (isERC4626) {
            // Deposit into underlying vault
            (bool success,) = address(underlyingVault).call(
                abi.encodeWithSignature("deposit(uint256,address)", assets, address(this))
            );
            require(success, "Deposit failed");
        }
        
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

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
        
        if (isERC4626) {
            // Withdraw from underlying vault
            (bool success,) = address(underlyingVault).call(
                abi.encodeWithSignature("withdraw(uint256,address,address)", assets, receiver, address(this))
            );
            require(success, "Withdraw failed");
        } else {
            IERC20(asset()).safeTransfer(receiver, assets);
        }
        
        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
