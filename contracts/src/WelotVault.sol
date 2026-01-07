// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEntropyV2, IEntropyConsumer} from "./interfaces/IEntropyV2.sol";

/// @title WelotVault
/// @notice No-loss savings lottery: deposit stablecoins, earn lottery tickets, win yield prizes.
///         Uses Pyth Entropy for verifiable randomness on Mantle Network.
///         Draw execution can be automated by an off-chain keeper calling `checkUpkeep`/`performUpkeep`.
/// @dev Supports multiple deposit tokens via separate vaults
contract WelotVault is ReentrancyGuard, Pausable, Ownable, IEntropyConsumer {
    using SafeERC20 for IERC20;

    // ══════════════════════════════════════════════════════════════════════════════
    // TYPES
    // ══════════════════════════════════════════════════════════════════════════════

    enum EpochStatus {
        Open,           // Accepting deposits
        Closed,         // Draw period started; draw lifecycle proceeds from here
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
        // NOTE: `totalDeposits` is the pool's *normalized* balance (18 decimals)
        // for winner-weighting via time-weighted deposits.
        // Prize accounting is token-specific via `poolTokenDeposits` and `poolTokenRewardIndex`.
        uint256 totalDeposits;
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

    struct PastWinner {
        uint256 epochId;
        uint64 timestamp;
        uint256 winningPoolId;
        uint256 totalPrizeNormalized; // 18 decimals
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

    // Token-aware pool accounting
    // token => poolId => total deposits (token decimals)
    mapping(address => mapping(uint256 => uint256)) public poolTokenDeposits;
    // token => poolId => reward index (1e18)
    mapping(address => mapping(uint256 => uint256)) public poolTokenRewardIndex;
    
    // Entropy request tracking
    mapping(uint64 => uint256) public entropyRequestToEpoch;

    // Optional keeper forwarder (if set, only this address can call performUpkeep)
    address public automationForwarder;

    // Past winners (ring buffer)
    uint256 public constant PAST_WINNERS_MAX = 52;
    uint256 public pastWinnersCount;
    mapping(uint256 => PastWinner) public pastWinners;

    // Epoch prize breakdown per token (token decimals)
    mapping(uint256 => mapping(address => uint256)) public epochTokenPrize;

    // ══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ══════════════════════════════════════════════════════════════════════════════

    event TokenAdded(address indexed token, address indexed yieldVault);
    event TokenRemoved(address indexed token);
    event PoolCreated(uint256 indexed poolId);
    event Deposited(address indexed user, address indexed token, uint256 indexed poolId, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 indexed poolId, uint256 amount);
    event DrawStarted(uint256 indexed epochId);
    event RandomnessRequested(uint256 indexed epochId, uint64 sequenceNumber);
    event RandomnessReceived(uint256 indexed epochId, bytes32 randomness);
    event WinnerSelected(uint256 indexed epochId, uint256 indexed winningPoolId, uint256 prize);
    event PastWinnerRecorded(uint256 indexed epochId, uint256 indexed winningPoolId, uint256 totalPrizeNormalized);
    event TokenPrizeRecorded(uint256 indexed epochId, address indexed token, uint256 prize);
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
    error InvalidAssignedPool();

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
        uint64 end = _getNextDrawTime();
        epochs[currentEpochId] = Epoch({
            start: start,
            end: end,
            status: EpochStatus.Open,
            entropySequence: 0,
            randomness: bytes32(0),
            prize: 0,
            winningPoolId: 0
        });

        // Create a fixed set of pools up-front. Pool assignment is deterministic,
        // so pool creation is disabled after deployment.
        for (uint256 i = 0; i < maxPools_; i++) {
            _createPool();
        }
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

    /// @notice Deterministically assign a user to one of the pre-created pools.
    /// @dev Uses the current `poolIds` array so assignment remains valid even if
    ///      pool ids are non-sequential (though this deployment creates 1..N).
    function assignedPoolId(address user) public view returns (uint256) {
        uint256 len = poolIds.length;
        if (len == 0) return 0;
        uint256 idx = uint256(uint160(user)) % len;
        return poolIds[idx];
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

    /// @notice Get next draw time based on drawInterval
    /// @dev For weekly draws uses Friday noon, otherwise uses interval-aligned boundaries
    function _getNextDrawTime() internal view returns (uint64) {
        // If drawInterval is 7 days (604800 seconds), use Friday noon scheduling
        if (drawInterval == 7 days) {
            return getNextFridayNoon();
        }
        // Otherwise use interval-aligned boundaries (for testing with shorter intervals)
        uint64 from = uint64(block.timestamp);
        uint64 remainder = from % drawInterval;
        if (remainder == 0) return from + drawInterval;
        return from + (drawInterval - remainder);
    }

    function _pendingPrize(address token, uint256 poolId, address user) internal view returns (uint256) {
        UserPosition storage pos = positions[token][poolId][user];
        if (!pools[poolId].exists) return 0;
        uint256 currentIndex = poolTokenRewardIndex[token][poolId];
        uint256 deltaIndex = currentIndex - pos.rewardIndexPaid;
        return pos.pendingPrize + (pos.deposits * deltaIndex) / 1e18;
    }

    function _to18(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * (10 ** (18 - decimals));
        return amount / (10 ** (decimals - 18));
    }

    function _poolBalanceNormalized(uint256 poolId) internal view returns (uint256 total) {
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            address token = supportedTokens[i];
            TokenConfig storage config = tokenConfigs[token];
            total += _to18(poolTokenDeposits[token][poolId], config.decimals);
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // CONVENIENCE VIEW FUNCTIONS (for frontend/tests)
    // ══════════════════════════════════════════════════════════════════════════════

    /// @notice Get user position for the user's assigned pool
    /// @dev Convenience wrapper for getUserPosition
    function userPosition(address token, address user) external view returns (uint256 deposited, uint256 claimable) {
        uint256 poolId = assignedPoolId(user);
        UserPosition storage pos = positions[token][poolId][user];
        deposited = pos.deposits;
        claimable = _pendingPrize(token, poolId, user);
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

    /// @notice Return up to `limit` most recent past winners (newest first).
    /// @dev Uses a ring buffer of size `PAST_WINNERS_MAX`.
    function getPastWinners(uint256 limit) external view returns (PastWinner[] memory) {
        uint256 count = pastWinnersCount;
        if (count == 0 || limit == 0) return new PastWinner[](0);

        uint256 available = count < PAST_WINNERS_MAX ? count : PAST_WINNERS_MAX;
        if (limit > available) limit = available;

        PastWinner[] memory out = new PastWinner[](limit);
        for (uint256 i = 0; i < limit; i++) {
            uint256 globalIdx = count - 1 - i;
            uint256 ringIdx = globalIdx % PAST_WINNERS_MAX;
            out[i] = pastWinners[ringIdx];
        }
        return out;
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // USER ACTIONS
    // ══════════════════════════════════════════════════════════════════════════════

    /// @notice Deposit tokens to the default pool
    function deposit(address token, uint256 amount) external whenNotPaused {
        uint256 poolId = assignedPoolId(msg.sender);
        depositTo(token, amount, poolId, msg.sender);
    }

    /// @notice Deposit tokens to a specific pool
    function depositTo(address token, uint256 amount, uint256 poolId, address recipient) 
        public nonReentrant whenNotPaused 
    {
        if (amount == 0) revert ZeroAmount();
        uint256 assigned = assignedPoolId(recipient);
        if (poolId != assigned) revert InvalidAssignedPool();
        if (!pools[poolId].exists) revert PoolDoesNotExist();
        
        TokenConfig storage config = tokenConfigs[token];
        if (!config.enabled) revert TokenNotSupported();

        _updateUserRewards(token, poolId, recipient);

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        config.yieldVault.deposit(amount, address(this));

        UserPosition storage pos = positions[token][poolId][recipient];
        pos.deposits += amount;

        Pool storage pool = pools[poolId];
        poolTokenDeposits[token][poolId] += amount;
        config.totalDeposits += amount;

        uint256 newBalanceNormalized = _poolBalanceNormalized(poolId);
        pool.totalDeposits = newBalanceNormalized;
        _updatePoolBalance(poolId, newBalanceNormalized);

        emit Deposited(recipient, token, poolId, amount);
    }

    /// @notice Withdraw tokens from the default pool
    function withdraw(address token, uint256 amount) external {
        uint256 poolId = assignedPoolId(msg.sender);
        withdrawFrom(token, amount, poolId);
    }

    /// @notice Withdraw tokens from a specific pool
    function withdrawFrom(address token, uint256 amount, uint256 poolId) public nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 assigned = assignedPoolId(msg.sender);
        if (poolId != assigned) revert InvalidAssignedPool();
        if (!pools[poolId].exists) revert PoolDoesNotExist();

        TokenConfig storage config = tokenConfigs[token];
        if (!config.enabled) revert TokenNotSupported();

        _updateUserRewards(token, poolId, msg.sender);

        UserPosition storage pos = positions[token][poolId][msg.sender];
        if (pos.deposits < amount) revert InsufficientBalance();

        pos.deposits -= amount;

        Pool storage pool = pools[poolId];
        poolTokenDeposits[token][poolId] -= amount;
        config.totalDeposits -= amount;

        uint256 newBalanceNormalized = _poolBalanceNormalized(poolId);
        pool.totalDeposits = newBalanceNormalized;
        _updatePoolBalance(poolId, newBalanceNormalized);

        config.yieldVault.withdraw(amount, msg.sender, address(this));

        emit Withdrawn(msg.sender, token, poolId, amount);
    }

    /// @notice Claim prize from the default pool
    function claimPrize(address token) external returns (uint256) {
        uint256 poolId = assignedPoolId(msg.sender);
        return claimPrizeFrom(token, poolId);
    }

    /// @notice Claim prize from a specific pool
    function claimPrizeFrom(address token, uint256 poolId) public nonReentrant returns (uint256 prize) {
        uint256 assigned = assignedPoolId(msg.sender);
        if (poolId != assigned) revert InvalidAssignedPool();
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
    // AUTOMATION / KEEPERS
    // ══════════════════════════════════════════════════════════════════════════════

    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData) {
        Epoch storage e = epochs[currentEpochId];

        if (e.status == EpochStatus.Open && block.timestamp >= e.end) {
            return (true, abi.encode(uint8(1))); // Close epoch
        }

        if (e.status == EpochStatus.Closed) {
            // Avoid keeper revert-loops when the vault is unfunded for the Entropy fee.
            uint256 fee = entropy.getFeeV2();
            if (address(this).balance < fee) return (false, "");
            return (true, abi.encode(uint8(2))); // Request randomness
        }

        if (e.status == EpochStatus.RandomnessReady) {
            return (true, abi.encode(uint8(3))); // Finalize draw
        }

        return (false, "");
    }

    function performUpkeep(bytes calldata performData) external {
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
        if (msg.sender != address(entropy)) return;
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
                uint256 winnerTokenDeposits = poolTokenDeposits[token][winningPoolId];
                if (winnerTokenDeposits > 0) {
                    poolTokenRewardIndex[token][winningPoolId] += (prize * 1e18) / winnerTokenDeposits;
                    config.totalUnclaimedPrizes += prize;
                    epochTokenPrize[currentEpochId][token] = prize;
                    emit TokenPrizeRecorded(currentEpochId, token, prize);
                    totalPrize += _to18(prize, config.decimals);
                }
            }
        }

        e.prize = totalPrize;
        e.winningPoolId = winningPoolId;

        emit WinnerSelected(currentEpochId, winningPoolId, totalPrize);

        // Record into ring buffer history for frontend
        if (winningPoolId != 0) {
            uint256 idx = pastWinnersCount % PAST_WINNERS_MAX;
            PastWinner memory pw = PastWinner({
                epochId: currentEpochId,
                timestamp: uint64(block.timestamp),
                winningPoolId: winningPoolId,
                totalPrizeNormalized: totalPrize
            });
            pastWinners[idx] = pw;
            pastWinnersCount++;
            emit PastWinnerRecorded(currentEpochId, winningPoolId, totalPrize);
        }

        // Start next epoch - Friday noon for production, interval-aligned for testing
        uint256 nextEpochId = currentEpochId + 1;
        uint64 nextStart = uint64(block.timestamp);
        uint64 nextEnd = _getNextDrawTime();

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

    function _createPool() internal returns (uint256 poolId) {
        if (poolIds.length >= maxPools) revert MaxPoolsReached();

        poolId = ++poolCount;
        pools[poolId] = Pool({
            exists: true,
            totalDeposits: 0,
            cumulative: 0,
            lastTimestamp: uint64(block.timestamp),
            lastBalance: 0
        });

        poolIds.push(poolId);
        emit PoolCreated(poolId);
    }

    function _updateUserRewards(address token, uint256 poolId, address user) internal {
        UserPosition storage pos = positions[token][poolId][user];

        uint256 currentIndex = poolTokenRewardIndex[token][poolId];
        uint256 deltaIndex = currentIndex - pos.rewardIndexPaid;
        if (deltaIndex > 0 && pos.deposits > 0) {
            pos.pendingPrize += (pos.deposits * deltaIndex) / 1e18;
        }
        pos.rewardIndexPaid = currentIndex;
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
