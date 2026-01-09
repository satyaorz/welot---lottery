// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MockAToken
/// @notice Mock implementation of Aave/Lendle aToken for local testing
/// @dev Simulates rebasing behavior via liquidity index growth
contract MockAToken is ERC20 {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlyingAsset;
    address public immutable pool;

    // Liquidity index starts at 1e27 (1 RAY in Aave terminology)
    uint256 public liquidityIndex = 1e27;
    uint256 public lastUpdateTimestamp;

    // APY for yield simulation (default 10% = 0.1e27)
    uint256 public supplyAPY = 0.1e27; // 10%

    // Scaled balances (internal accounting)
    mapping(address => uint256) private _scaledBalances;
    uint256 private _scaledTotalSupply;

    error MockAToken__OnlyPool();
    error MockAToken__NonTransferable();
    error MockAToken__NoApprovalNeeded();

    constructor(IERC20 _underlyingAsset, address _pool, string memory name, string memory symbol)
        ERC20(name, symbol)
    {
        underlyingAsset = _underlyingAsset;
        pool = _pool;
        lastUpdateTimestamp = block.timestamp;
    }

    /// @notice Mint aTokens (called by MockLendlePool on supply)
    /// @param user The user receiving aTokens
    /// @param amount The amount of underlying assets being supplied
    function mint(address user, uint256 amount) external onlyPool {
        _updateIndex();

        uint256 scaledAmount = _rayDiv(amount, liquidityIndex);
        _scaledBalances[user] += scaledAmount;
        _scaledTotalSupply += scaledAmount;

        emit Transfer(address(0), user, amount);
    }

    /// @notice Burn aTokens (called by MockLendlePool on withdraw)
    /// @param user The user whose aTokens are being burned
    /// @param amount The amount of underlying assets being withdrawn
    function burn(address user, uint256 amount) external onlyPool {
        _updateIndex();

        uint256 scaledAmount = _rayDiv(amount, liquidityIndex);
        _scaledBalances[user] -= scaledAmount;
        _scaledTotalSupply -= scaledAmount;

        emit Transfer(user, address(0), amount);
    }

    /// @notice Transfer underlying out of the aToken contract (called by pool on withdraw)
    function transferUnderlyingTo(address to, uint256 amount) external onlyPool {
        underlyingAsset.safeTransfer(to, amount);
    }

    /// @notice Get the balance of a user (scaled balance * liquidity index)
    /// @dev This is where the magic happens - balance grows automatically via index
    function balanceOf(address account) public view override returns (uint256) {
        uint256 currentIndex = _getCurrentIndex();
        return _rayMul(_scaledBalances[account], currentIndex);
    }

    /// @notice Get total supply (scaled total supply * liquidity index)
    function totalSupply() public view override returns (uint256) {
        uint256 currentIndex = _getCurrentIndex();
        return _rayMul(_scaledTotalSupply, currentIndex);
    }

    /// @notice Get the scaled balance (internal)
    function scaledBalanceOf(address account) external view returns (uint256) {
        return _scaledBalances[account];
    }

    /// @notice Get the scaled total supply (internal)
    function scaledTotalSupply() external view returns (uint256) {
        return _scaledTotalSupply;
    }

    /// @notice Update the liquidity index (simulates interest accrual)
    /// @dev Called automatically on mint/burn, or manually for testing
    function updateIndex() external {
        _updateIndex();
    }

    /// @notice Set the supply APY for testing
    function setSupplyAPY(uint256 newAPY) external {
        _updateIndex();
        supplyAPY = newAPY;
    }

    // ========== INTERNAL FUNCTIONS ==========

    function _updateIndex() internal {
        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp;
        if (timeElapsed == 0) return;

        uint256 oldIndex = liquidityIndex;
        uint256 oldTotal = _rayMul(_scaledTotalSupply, oldIndex);

        // Calculate linear interest: index *= (1 + APY * timeElapsed / SECONDS_PER_YEAR)
        // Simplified for testing: assume 365 days = 31536000 seconds
        uint256 interest = _rayMul(supplyAPY, (timeElapsed * 1e27) / 31536000);
        uint256 newIndex = _rayMul(oldIndex, 1e27 + interest);
        liquidityIndex = newIndex;
        lastUpdateTimestamp = block.timestamp;

        // Best-effort backing of accrued interest by minting underlying to this contract.
        // Works with `MockERC20` and any underlying that exposes `mint(address,uint256)`.
        uint256 newTotal = _rayMul(_scaledTotalSupply, newIndex);
        uint256 delta = newTotal > oldTotal ? newTotal - oldTotal : 0;
        if (delta > 0) {
            // Ignore failure for non-mintable underlyings.
            (bool ok,) = address(underlyingAsset).call(
                abi.encodeWithSignature("mint(address,uint256)", address(this), delta)
            );
            ok;
        }
    }

    function _getCurrentIndex() internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastUpdateTimestamp;
        if (timeElapsed == 0) return liquidityIndex;

        uint256 interest = _rayMul(supplyAPY, (timeElapsed * 1e27) / 31536000);
        return _rayMul(liquidityIndex, 1e27 + interest);
    }

    // ========== RAY MATH (Aave's high-precision math) ==========

    function _rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b + 0.5e27) / 1e27;
    }

    function _rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * 1e27 + b / 2) / b;
    }

    // ========== MODIFIERS ==========

    modifier onlyPool() {
        if (msg.sender != pool) revert MockAToken__OnlyPool();
        _;
    }

    // ========== OVERRIDES (disable transfers for simplicity) ==========

    function transfer(address, uint256) public pure override returns (bool) {
        revert MockAToken__NonTransferable();
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert MockAToken__NonTransferable();
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert MockAToken__NoApprovalNeeded();
    }
}
