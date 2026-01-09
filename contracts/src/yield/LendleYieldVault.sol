// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ILendlePool.sol";

/// @title LendleYieldVault
/// @notice ERC4626 vault that deposits assets into Lendle for yield generation
/// @dev Supports USDC, USDT, and other assets supported by Lendle on Mantle Network
contract LendleYieldVault is ERC4626 {
    using SafeERC20 for IERC20;

    error LendleYieldVault__ZeroPoolAddress();
    error LendleYieldVault__ZeroATokenAddress();
    error LendleYieldVault__WithdrawAmountMismatch();

    /// @notice The Lendle lending pool contract
    ILendlePool public immutable lendlePool;

    /// @notice The aToken (interest-bearing token) received from Lendle
    IERC20 public immutable aToken;

    /// @notice Emitted when assets are deposited into Lendle
    event DepositedToLendle(uint256 amount);

    /// @notice Emitted when assets are withdrawn from Lendle
    event WithdrawnFromLendle(uint256 amount);

    /// @dev Constructor initializes the ERC4626 vault
    /// @param _asset The underlying asset (e.g., USDC, USDT)
    /// @param _lendlePool The address of the Lendle Pool contract
    /// @param _aToken The address of the corresponding aToken for the asset
    /// @param _name The name of the vault token (e.g., "Lendle USDC Vault")
    /// @param _symbol The symbol of the vault token (e.g., "lendleUSDC")
    constructor(
        IERC20 _asset,
        ILendlePool _lendlePool,
        IERC20 _aToken,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        if (address(_lendlePool) == address(0)) revert LendleYieldVault__ZeroPoolAddress();
        if (address(_aToken) == address(0)) revert LendleYieldVault__ZeroATokenAddress();

        lendlePool = _lendlePool;
        aToken = _aToken;

        // Approve Lendle pool to spend the asset (infinite approval for gas efficiency)
        SafeERC20.forceApprove(IERC20(_asset), address(_lendlePool), type(uint256).max);
    }

    /// @notice Returns the total assets held by the vault
    /// @dev Total assets = aToken balance (which includes principal + accrued interest)
    /// @return The total amount of underlying assets
    function totalAssets() public view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /// @notice Returns the maximum amount of assets that can be withdrawn by the owner
    /// @dev Capped by available liquidity in the Lendle pool
    /// @param owner The address of the vault share owner
    /// @return The maximum withdrawable amount
    function maxWithdraw(address owner) public view override returns (uint256) {
        // User's share of vault assets
        uint256 userAssets = convertToAssets(balanceOf(owner));

        // Available liquidity in Lendle pool (underlying asset balance in aToken contract)
        // Note: In Aave/Lendle, liquidity = underlying.balanceOf(aToken)
        uint256 availableLiquidity = IERC20(asset()).balanceOf(address(aToken));

        // Return the minimum of user's assets and available liquidity
        return userAssets < availableLiquidity ? userAssets : availableLiquidity;
    }

    /// @notice Returns the maximum amount of shares that can be redeemed by the owner
    /// @dev Capped by available liquidity in the Lendle pool
    /// @param owner The address of the vault share owner
    /// @return The maximum redeemable shares
    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 maxAssets = maxWithdraw(owner);
        return convertToShares(maxAssets);
    }

    /// @dev Internal deposit logic: deposits assets into Lendle and mints vault shares
    /// @param caller The address initiating the deposit
    /// @param receiver The address receiving the vault shares
    /// @param assets The amount of assets to deposit
    /// @param shares The amount of vault shares to mint
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        // Transfer assets from caller to vault
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);

        // Supply assets to Lendle (vault receives aTokens in return)
        lendlePool.supply(asset(), assets, address(this), 0);

        // Mint vault shares to receiver
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
        emit DepositedToLendle(assets);
    }

    /// @dev Internal withdraw logic: burns vault shares and withdraws assets from Lendle
    /// @param caller The address initiating the withdrawal
    /// @param receiver The address receiving the withdrawn assets
    /// @param owner The owner of the vault shares being redeemed
    /// @param assets The amount of assets to withdraw
    /// @param shares The amount of vault shares to burn
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        // If caller is not the owner, check and spend allowance
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // Burn vault shares from owner
        _burn(owner, shares);

        // Withdraw assets from Lendle (burns aTokens, returns underlying)
        uint256 withdrawn = lendlePool.withdraw(asset(), assets, receiver);

        // Ensure we withdrew the expected amount
        if (withdrawn != assets) revert LendleYieldVault__WithdrawAmountMismatch();

        emit Withdraw(caller, receiver, owner, assets, shares);
        emit WithdrawnFromLendle(withdrawn);
    }
}
