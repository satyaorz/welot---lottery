// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AutomationCompatibleInterface} from "@chainlink/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEntropyV2, IEntropyConsumer} from "./interfaces/IEntropyV2.sol";

/// @title WelotVault
/// @notice No-loss savings lottery: deposit stablecoins, earn lottery tickets, win yield prizes.
///         Integrated with Chainlink Automation for automatic weekly draws.
///         Uses Pyth Entropy for verifiable randomness on Mantle Network.
/// @dev Supports multiple deposit tokens via separate vaults
contract WelotVault is ReentrancyGuard, Pausable, Ownable, AutomationCompatibleInterface, IEntropyConsumer {
    using SafeERC20 for IERC20;

    // ══════════════════════════════════════════════════════════════════════════════
    // TYPES
    // ══════════════════════════════════════════════════════════════════════════════

    enum EpochStatus {
        Open,           // Accepting deposits
        Closed,         // Draw period started, no more deposits for this epoch
        RandomnessRequested, // Waiting for VRF/Entropy callback
        RandomnessReady      // Random number received, ready to finalize
    }

    struct Epoch {
        uint64 start;
        uint64 end;
        EpochStatus status;
        uint64 entropySequence;
        bytes32 randomness;
        uint256 prize;
        uint256 winningPoolId;
    }

    struct Pool {
        bool exists;
        address creator;
        uint256 totalDeposits;
        uint256 rewardIndex;
        uint256 cumulative;
        uint64 lastTimestamp;
        uint256 lastBalance;
    }

    struct UserPosition {
        uint256 deposits;
        uint256 rewardIndexPaid;
        uint256 pendingPrize;
    }

    struct TokenConfig {
        bool enabled;
        IERC4626 yieldVault;
        uint8 decimals;
        uint256 totalDeposits;
        uint256 totalUnclaimedPrizes;
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // STATE
    // ══════════════════════════════════════════════════════════════════════════════

    // Pyth Entropy for randomness (supported on Mantle)
    IEntropyV2 public immutable entropy;
    
    // Draw configuration
    uint64 public immutable drawInterval;
    uint256 public immutable maxPools;

    // Friday noon (UTC) as draw time - default 12:00 UTC
    uint8 public constant DRAW_HOUR = 12;
    uint8 public constant DRAW_DAY = 5; // Friday (0 = Sunday)

    // Supported tokens
    mapping(address => TokenConfig) public tokenConfigs;
    address[] public supportedTokens;

    // Global pool tracking
    uint256 public poolCount;
    uint256 public currentEpochId;

    mapping(uint256 => Epoch) public epochs;
    mapping(uint256 => Pool) public pools;
    uint256[] public poolIds;
    
    // Position: token => poolId => user => position
    mapping(address => mapping(uint256 => mapping(address => UserPosition))) public positions;
    
    // Entropy request tracking
    mapping(uint64 => uint256) public entropyRequestToEpoch;

    // Chainlink Automation forwarder
    address public automationForwarder;

    // ══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ══════════════════════════════════════════════════════════════════════════════

    event TokenAdded(address indexed token, address indexed yieldVault);
    event TokenRemoved(address indexed token);
    event PoolCreated(uint256 indexed poolId, address indexed creator);
    event Deposited(address indexed user, address indexed token, uint256 indexed poolId, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 indexed poolId, uint256 amount);
    event DrawStarted(uint256 indexed epochId);
    event RandomnessRequested(uint256 indexed epochId, uint64 sequenceNumber);
    event RandomnessReceived(uint256 indexed epochId, bytes32 randomness);
    event WinnerSelected(uint256 indexed epochId, uint256 indexed winningPoolId, uint256 prize);
    event PrizeClaimed(address indexed user, address indexed token, uint256 indexed poolId, uint256 amount);
    event AutomationForwarderSet(address indexed forwarder);

    // ══════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ══════════════════════════════════════════════════════════════════════════════

    error PoolDoesNotExist();
    error MaxPoolsReached();
    error InvalidEpochState();
    error DrawNotReady();
    error ZeroAmount();
    error InsufficientBalance();
    error NotAutomationForwarder();
    error TokenNotSupported();
    error TokenAlreadySupported();
    error InvalidToken();
    error InsufficientFee();

    // ══════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ══════════════════════════════════════════════════════════════════════════════

    constructor(
        IEntropyV2 entropy_,
        uint64 drawIntervalSeconds_,
        uint256 maxPools_
    ) Ownable(msg.sender) {
        require(address(entropy_) != address(0), "Invalid entropy");
        require(drawIntervalSeconds_ > 0, "Invalid draw interval");

        entropy = entropy_;
        drawInterval = drawIntervalSeconds_;
        maxPools = maxPools_;

        // Initialize first epoch
        currentEpochId = 1;
        uint64 start = uint64(block.timestamp);
        epochs[currentEpochId] = Epoch({
            start: start,
            end: start + drawInterval,
            status: EpochStatus.Open,
            entropySequence: 0,
            randomness: bytes32(0),
            prize: 0,
            winningPoolId: 0
        });

        // Create default pool
        _createPool(msg.sender);
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // ADMIN
    // ══════════════════════════════════════════════════════════════════════════════

    /// @notice Add a supported deposit token with its yield vault
    /// @param token The ERC20 token address
    /// @param yieldVault The ERC4626 vault that generates yield
    function addSupportedToken(address token, IERC4626 yieldVault) external onlyOwner {
        if (token == address(0)) revert InvalidToken();
        if (tokenConfigs[token].enabled) revert TokenAlreadySupported();
        if (address(yieldVault.asset()) != token) revert InvalidToken();

        // Get decimals from token
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = success && data.length == 32 ? abi.decode(data, (uint8)) : 18;

        tokenConfigs[token] = TokenConfig({
            enabled: true,
            yieldVault: yieldVault,
            decimals: decimals,
            totalDeposits: 0,
            totalUnclaimedPrizes: 0
        });

        supportedTokens.push(token);

        // Approve vault for max deposits
        IERC20(token).forceApprove(address(yieldVault), type(uint256).max);

        emit TokenAdded(token, address(yieldVault));
    }

    /// @notice Remove a supported token (only if no deposits)
    function removeSupportedToken(address token) external onlyOwner {
        TokenConfig storage config = tokenConfigs[token];
        if (!config.enabled) revert TokenNotSupported();
        require(config.totalDeposits == 0, "Has deposits");

        config.enabled = false;

        // Remove from array
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[supportedTokens.length - 1];
                supportedTokens.pop();
                break;
            }
        }

        emit TokenRemoved(token);
    }

    function setAutomationForwarder(address forwarder) external onlyOwner {
        automationForwarder = forwarder;
        emit AutomationForwarderSet(forwarder);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Create a new pool
    function createPool() external returns (uint256 poolId) {
        return _createPool(msg.sender);
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // VIEWS
    // ══════════════════════════════════════════════════════════════════════════════

    function poolIdsLength() external view returns (uint256) {
        return poolIds.length;
    }

    function supportedTokensLength() external view returns (uint256) {
        return supportedTokens.length;
    }

    function getSupportedToken(uint256 index) external view returns (address) {
        return supportedTokens[index];
    }

    /// @notice Get total assets for a specific token across all vaults
    function totalAssets(address token) public view returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];
        if (!config.enabled) return 0;
        
        uint256 shares = config.yieldVault.balanceOf(address(this));
        return config.yieldVault.convertToAssets(shares);
    }

    /// @notice Get total deposits across all tokens (normalized to 18 decimals)
    function totalDepositsNormalized() public view returns (uint256 total) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            TokenConfig storage config = tokenConfigs[token];
            // Normalize to 18 decimals
            total += config.totalDeposits * (10 ** (18 - config.decimals));
        }
    }

    /// @notice Get total unclaimed prizes across all tokens (normalized to 18 decimals)
    function totalUnclaimedPrizesNormalized() public view returns (uint256 total) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            TokenConfig storage config = tokenConfigs[token];
            total += config.totalUnclaimedPrizes * (10 ** (18 - config.decimals));
        }
    }

    /// @notice Get current prize pool for a specific token
    function currentPrizePool(address token) public view returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];
        if (!config.enabled) return 0;
        
        uint256 assets = totalAssets(token);
        uint256 liabilities = config.totalDeposits + config.totalUnclaimedPrizes;
        return assets > liabilities ? assets - liabilities : 0;
    }

    /// @notice Get total prize pool across all tokens (normalized)
    function currentPrizePoolTotal() public view returns (uint256 total) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            TokenConfig storage config = tokenConfigs[token];
            uint256 prize = currentPrizePool(token);
            total += prize * (10 ** (18 - config.decimals));
        }
    }

    function getEpoch(uint256 epochId) external view returns (Epoch memory) {
        return epochs[epochId];
    }

    function getCurrentEpoch() external view returns (Epoch memory) {
        return epochs[currentEpochId];
    }

    function getUserPosition(address token, uint256 poolId, address user) 
        external view returns (uint256 deposited, uint256 claimable) 
    {
        UserPosition storage pos = positions[token][poolId][user];
        deposited = pos.deposits;
        claimable = _pendingPrize(token, poolId, user);
    }

    function getTimeUntilDraw() external view returns (uint256) {
        Epoch storage e = epochs[currentEpochId];
        if (block.timestamp >= e.end) return 0;
        return e.end - block.timestamp;
    }

    /// @notice Calculate next Friday noon UTC
    function getNextFridayNoon() public view returns (uint64) {
        uint256 currentTime = block.timestamp;
        uint256 dayOfWeek = (currentTime / 1 days + 4) % 7; // 0 = Sunday
        uint256 daysUntilFriday = (DRAW_DAY + 7 - dayOfWeek) % 7;
        if (daysUntilFriday == 0) {
            // Today is Friday, check if we've passed noon
            uint256 todayNoon = (currentTime / 1 days) * 1 days + DRAW_HOUR * 1 hours;
            if (currentTime >= todayNoon) {
                daysUntilFriday = 7; // Next Friday
            }
        }
        uint256 nextFriday = (currentTime / 1 days + daysUntilFriday) * 1 days + DRAW_HOUR * 1 hours;
        return uint64(nextFriday);
    }

    function _pendingPrize(address token, uint256 poolId, address user) internal view returns (uint256) {
        UserPosition storage pos = positions[token][poolId][user];
        Pool storage pool = pools[poolId];
        if (!pool.exists) return 0;
        uint256 deltaIndex = pool.rewardIndex - pos.rewardIndexPaid;
        return pos.pendingPrize + (pos.deposits * deltaIndex) / 1e18;
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // CONVENIENCE VIEW FUNCTIONS (for frontend/tests)
    // ══════════════════════════════════════════════════════════════════════════════

    /// @notice Get user position for the default pool (1)
    /// @dev Convenience wrapper for getUserPosition
    function userPosition(address token, address user) external view returns (uint256 deposited, uint256 claimable) {
        UserPosition storage pos = positions[token][1][user];
        deposited = pos.deposits;
        claimable = _pendingPrize(token, 1, user);
    }

    /// @notice Total deposits for a token (sum across all pools)
    function totalDeposits(address token) external view returns (uint256) {
        return tokenConfigs[token].totalDeposits;
    }

    /// @notice Prize pool for a token (alias for currentPrizePool)
    function prizePool(address token) external view returns (uint256) {
        return currentPrizePool(token);
    }

    /// @notice Get current epoch status
    function epochStatus() external view returns (EpochStatus) {
        return epochs[currentEpochId].status;
    }

    /// @notice Get current epoch number
    function currentEpoch() external view returns (uint256) {
        return currentEpochId;
    }

    /// @notice Get list of all supported tokens
    function getSupportedTokens() external view returns (address[] memory) {
        return supportedTokens;
    }

    /// @notice Configure a token (add or update)
    /// @dev Convenience method that combines add/update logic
    function configureToken(address token, address yieldVault, bool enabled, uint8 decimals) external onlyOwner {
        if (token == address(0)) revert InvalidToken();
        
        TokenConfig storage config = tokenConfigs[token];
        
        if (!config.enabled && enabled) {
            // Adding new token
            IERC4626 vault = IERC4626(yieldVault);
            if (address(vault.asset()) != token) revert InvalidToken();
            
            config.enabled = true;
            config.yieldVault = vault;
            config.decimals = decimals;
            config.totalDeposits = 0;
            config.totalUnclaimedPrizes = 0;
            
            supportedTokens.push(token);
            IERC20(token).forceApprove(yieldVault, type(uint256).max);
            
            emit TokenAdded(token, yieldVault);
        } else if (config.enabled && !enabled) {
            // Disabling token
            require(config.totalDeposits == 0, "Has deposits");
            config.enabled = false;
            
            // Remove from array
            for (uint256 i = 0; i < supportedTokens.length; i++) {
                if (supportedTokens[i] == token) {
                    supportedTokens[i] = supportedTokens[supportedTokens.length - 1];
                    supportedTokens.pop();
                    break;
                }
            }
            emit TokenRemoved(token);
        }
        // If already enabled, just update decimals
        if (enabled) {
            config.decimals = decimals;
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // USER ACTIONS
    // ══════════════════════════════════════════════════════════════════════════════

    /// @notice Deposit tokens to the default pool
    function deposit(address token, uint256 amount) external whenNotPaused {
        depositTo(token, amount, 1, msg.sender);
    }

    /// @notice Deposit tokens to a specific pool
    function depositTo(address token, uint256 amount, uint256 poolId, address recipient) 
        public nonReentrant whenNotPaused 
    {
        if (amount == 0) revert ZeroAmount();
        if (!pools[poolId].exists) revert PoolDoesNotExist();
        
        TokenConfig storage config = tokenConfigs[token];
        if (!config.enabled) revert TokenNotSupported();

        _updateUserRewards(token, poolId, recipient);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        config.yieldVault.deposit(amount, address(this));

        UserPosition storage pos = positions[token][poolId][recipient];
        pos.deposits += amount;

        Pool storage pool = pools[poolId];
        pool.totalDeposits += amount;
        config.totalDeposits += amount;

        _updatePoolBalance(poolId, pool.totalDeposits);

        emit Deposited(recipient, token, poolId, amount);
    }

    /// @notice Withdraw tokens from the default pool
    function withdraw(address token, uint256 amount) external {
        withdrawFrom(token, amount, 1);
    }

    /// @notice Withdraw tokens from a specific pool
    function withdrawFrom(address token, uint256 amount, uint256 poolId) public nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!pools[poolId].exists) revert PoolDoesNotExist();

        TokenConfig storage config = tokenConfigs[token];
        if (!config.enabled) revert TokenNotSupported();

        _updateUserRewards(token, poolId, msg.sender);

        UserPosition storage pos = positions[token][poolId][msg.sender];
        if (pos.deposits < amount) revert InsufficientBalance();

        pos.deposits -= amount;

        Pool storage pool = pools[poolId];
        pool.totalDeposits -= amount;
        config.totalDeposits -= amount;

        _updatePoolBalance(poolId, pool.totalDeposits);

        config.yieldVault.withdraw(amount, msg.sender, address(this));

        emit Withdrawn(msg.sender, token, poolId, amount);
    }

    /// @notice Claim prize from the default pool
    function claimPrize(address token) external returns (uint256) {
        return claimPrizeFrom(token, 1);
    }

    /// @notice Claim prize from a specific pool
    function claimPrizeFrom(address token, uint256 poolId) public nonReentrant returns (uint256 prize) {
        if (!pools[poolId].exists) revert PoolDoesNotExist();

        TokenConfig storage config = tokenConfigs[token];
        if (!config.enabled) revert TokenNotSupported();

        _updateUserRewards(token, poolId, msg.sender);

        UserPosition storage pos = positions[token][poolId][msg.sender];
        prize = pos.pendingPrize;
        if (prize == 0) return 0;

        pos.pendingPrize = 0;
        config.totalUnclaimedPrizes -= prize;

        config.yieldVault.withdraw(prize, msg.sender, address(this));

        emit PrizeClaimed(msg.sender, token, poolId, prize);
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // CHAINLINK AUTOMATION
    // ══════════════════════════════════════════════════════════════════════════════

    function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
        Epoch storage e = epochs[currentEpochId];

        if (e.status == EpochStatus.Open && block.timestamp >= e.end) {
            return (true, abi.encode(uint8(1))); // Close epoch
        }

        if (e.status == EpochStatus.Closed) {
            return (true, abi.encode(uint8(2))); // Request randomness
        }

        if (e.status == EpochStatus.RandomnessReady) {
            return (true, abi.encode(uint8(3))); // Finalize draw
        }

        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external override {
        if (automationForwarder != address(0) && msg.sender != automationForwarder) {
            revert NotAutomationForwarder();
        }

        uint8 action = abi.decode(performData, (uint8));

        if (action == 1) {
            _closeEpoch();
        } else if (action == 2) {
            _requestRandomness();
        } else if (action == 3) {
            _finalizeDraw();
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // DRAW LIFECYCLE
    // ══════════════════════════════════════════════════════════════════════════════

    function closeEpoch() external {
        _closeEpoch();
    }

    function requestRandomness() external payable {
        _requestRandomness();
    }

    function finalizeDraw() external {
        _finalizeDraw();
    }

    function _closeEpoch() internal {
        Epoch storage e = epochs[currentEpochId];
        if (e.status != EpochStatus.Open) revert InvalidEpochState();
        if (block.timestamp < e.end) revert DrawNotReady();

        e.status = EpochStatus.Closed;
        _accrueAllPools();

        emit DrawStarted(currentEpochId);
    }

    function _requestRandomness() internal {
        Epoch storage e = epochs[currentEpochId];
        if (e.status != EpochStatus.Closed) revert InvalidEpochState();

        uint256 fee = entropy.getFeeV2();
        if (address(this).balance < fee) revert InsufficientFee();

        uint64 sequenceNumber = entropy.requestV2{value: fee}();

        e.entropySequence = sequenceNumber;
        e.status = EpochStatus.RandomnessRequested;

        entropyRequestToEpoch[sequenceNumber] = currentEpochId;

        emit RandomnessRequested(currentEpochId, sequenceNumber);
    }

    /// @notice Entropy callback - MUST NOT REVERT
    function entropyCallback(uint64 sequenceNumber, address /*provider*/, bytes32 randomNumber) external override {
        uint256 epochId = entropyRequestToEpoch[sequenceNumber];
        if (epochId == 0) return;

        Epoch storage e = epochs[epochId];
        if (e.status != EpochStatus.RandomnessRequested) return;

        e.randomness = randomNumber;
        e.status = EpochStatus.RandomnessReady;

        emit RandomnessReceived(epochId, randomNumber);
    }

    function _finalizeDraw() internal {
        Epoch storage e = epochs[currentEpochId];
        if (e.status != EpochStatus.RandomnessReady) revert DrawNotReady();

        _accrueAllPools();

        uint256 winningPoolId = _selectWinner(e.randomness);
        
        // Distribute prizes for each token
        uint256 totalPrize = 0;
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            TokenConfig storage config = tokenConfigs[token];
            
            uint256 prize = currentPrizePool(token);
            if (prize > 0 && winningPoolId != 0) {
                Pool storage pool = pools[winningPoolId];
                if (pool.totalDeposits > 0) {
                    pool.rewardIndex += (prize * 1e18) / pool.totalDeposits;
                    config.totalUnclaimedPrizes += prize;
                    totalPrize += prize * (10 ** (18 - config.decimals));
                }
            }
        }

        e.prize = totalPrize;
        e.winningPoolId = winningPoolId;

        emit WinnerSelected(currentEpochId, winningPoolId, totalPrize);

        // Start next epoch - target next Friday noon
        uint256 nextEpochId = currentEpochId + 1;
        uint64 nextEnd = getNextFridayNoon();
        uint64 nextStart = uint64(block.timestamp);

        currentEpochId = nextEpochId;
        epochs[nextEpochId] = Epoch({
            start: nextStart,
            end: nextEnd,
            status: EpochStatus.Open,
            entropySequence: 0,
            randomness: bytes32(0),
            prize: 0,
            winningPoolId: 0
        });
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ══════════════════════════════════════════════════════════════════════════════

    function _createPool(address creator) internal returns (uint256 poolId) {
        if (poolIds.length >= maxPools) revert MaxPoolsReached();

        poolId = ++poolCount;
        pools[poolId] = Pool({
            exists: true,
            creator: creator,
            totalDeposits: 0,
            rewardIndex: 0,
            cumulative: 0,
            lastTimestamp: uint64(block.timestamp),
            lastBalance: 0
        });

        poolIds.push(poolId);
        emit PoolCreated(poolId, creator);
    }

    function _updateUserRewards(address token, uint256 poolId, address user) internal {
        Pool storage pool = pools[poolId];
        UserPosition storage pos = positions[token][poolId][user];

        uint256 deltaIndex = pool.rewardIndex - pos.rewardIndexPaid;
        if (deltaIndex > 0 && pos.deposits > 0) {
            pos.pendingPrize += (pos.deposits * deltaIndex) / 1e18;
        }
        pos.rewardIndexPaid = pool.rewardIndex;
    }

    function _accrueAllPools() internal {
        uint256 len = poolIds.length;
        for (uint256 i = 0; i < len; i++) {
            _accruePool(poolIds[i]);
        }
    }

    function _accruePool(uint256 poolId) internal {
        Pool storage pool = pools[poolId];
        if (!pool.exists) return;

        uint64 ts = uint64(block.timestamp);
        if (ts <= pool.lastTimestamp) return;

        uint256 dt = ts - pool.lastTimestamp;
        pool.cumulative += pool.lastBalance * dt;
        pool.lastTimestamp = ts;
    }

    function _updatePoolBalance(uint256 poolId, uint256 newBalance) internal {
        _accruePool(poolId);
        pools[poolId].lastBalance = newBalance;
    }

    function _selectWinner(bytes32 randomness) internal view returns (uint256) {
        uint256 len = poolIds.length;
        if (len == 0) return 0;

        uint256 totalWeight = 0;
        uint256[] memory weights = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            uint256 w = pools[poolIds[i]].cumulative;
            weights[i] = w;
            totalWeight += w;
        }

        if (totalWeight == 0) return 0;

        uint256 r = uint256(randomness) % totalWeight;
        for (uint256 i = 0; i < len; i++) {
            if (r < weights[i]) return poolIds[i];
            r -= weights[i];
        }

        return poolIds[len - 1];
    }

    /// @notice Allow contract to receive ETH for Entropy fees
    receive() external payable {}
}
