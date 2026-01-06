// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC4626} from "../../src/interfaces/IERC4626.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

/// @notice Minimal ERC-4626 mock with 1:1 exchange rate unless yield is injected.
contract MockERC4626 is IERC4626 {
    string public override name;
    string public override symbol;
    uint8 public override decimals;

    IERC20 public immutable underlying;

    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    // total underlying held by vault
    uint256 internal _totalUnderlying;

    constructor(IERC20 asset_, string memory name_, string memory symbol_, uint8 decimals_) {
        underlying = asset_;
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function asset() external view override returns (address) {
        return address(underlying);
    }

    function totalAssets() external view override returns (uint256) {
        return _totalUnderlying;
    }

    function convertToShares(uint256 assets) external view override returns (uint256) {
        return _convertToShares(assets, false);
    }

    function convertToAssets(uint256 shares) external view override returns (uint256) {
        return _convertToAssets(shares);
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "ALLOW");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {
        shares = _convertToShares(assets, false);
        require(shares > 0, "ZERO_SHARES");
        require(underlying.transferFrom(msg.sender, address(this), assets), "TF");
        _totalUnderlying += assets;
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {
        shares = _convertToShares(assets, true);
        _spendAllowanceIfNeeded(owner, msg.sender, shares);
        _burn(owner, shares);
        require(_totalUnderlying >= assets, "INSUF_ASSETS");
        _totalUnderlying -= assets;
        require(underlying.transfer(receiver, assets), "T");
    }

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets) {
        assets = _convertToAssets(shares);
        _spendAllowanceIfNeeded(owner, msg.sender, shares);
        _burn(owner, shares);
        require(_totalUnderlying >= assets, "INSUF_ASSETS");
        _totalUnderlying -= assets;
        require(underlying.transfer(receiver, assets), "T");
    }

    /// @notice Inject yield into the vault (simulates strategy yield).
    function donateYield(uint256 assets) external {
        require(underlying.transferFrom(msg.sender, address(this), assets), "TF");
        _totalUnderlying += assets;
    }

    function _mint(address to, uint256 amount) internal {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function _burn(address from, uint256 amount) internal {
        require(balanceOf[from] >= amount, "BAL");
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "BAL");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function _spendAllowanceIfNeeded(address owner, address spender, uint256 amount) internal {
        if (spender == owner) return;
        uint256 allowed = allowance[owner][spender];
        require(allowed >= amount, "ALLOW");
        if (allowed != type(uint256).max) {
            allowance[owner][spender] = allowed - amount;
        }
    }

    function _convertToShares(uint256 assets, bool roundUp) internal view returns (uint256 shares) {
        if (assets == 0) return 0;
        if (totalSupply == 0 || _totalUnderlying == 0) return assets;

        shares = (assets * totalSupply) / _totalUnderlying;
        if (roundUp) {
            // if (assets * totalSupply) is not divisible by _totalUnderlying, round up
            if ((shares * _totalUnderlying) < (assets * totalSupply)) {
                shares += 1;
            }
        }
    }

    function _convertToAssets(uint256 shares) internal view returns (uint256 assets) {
        if (shares == 0) return 0;
        if (totalSupply == 0) return shares;
        assets = (shares * _totalUnderlying) / totalSupply;
    }
}
