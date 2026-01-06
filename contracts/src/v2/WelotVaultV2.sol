// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AutomationCompatibleInterface} from "@chainlink/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

import {IERC4626} from "../interfaces/IERC4626.sol";
import {IEntropyV2} from "../interfaces/IEntropyV2.sol";

/// @title WelotVaultV2
/// @notice No-loss savings lottery: deposit stablecoins, earn lottery tickets, win yield prizes.
///         Integrated with Chainlink Automation for automatic weekly draws.
contract WelotVaultV2 is ReentrancyGuard, Pausable, Ownable, AutomationCompatibleInterface {
    using SafeERC20 for IERC20;

    // ══════════════════════════════════════════════════════════════════════════════
    // TYPES
    // ══════════════════════════════════════════════════════════════════════════════

    enum EpochStatus {
        Open,
        Closed,
        RandomnessRequested,
        RandomnessReady
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

    // ══════════════════════════════════════════════════════════════════════════════
    // STATE
    // ══════════════════════════════════════════════════════════════════════════════

    IERC20 public immutable depositToken;
    IERC4626 public immutable yieldVault;
    IEntropyV2 public immutable entropy;

    uint64 public immutable drawInterval;
    uint256 public immutable maxPools;

    uint256 public totalDeposits;
    uint256 public totalUnclaimedPrizes;

    uint256 public poolCount;
    uint256 public currentEpochId;

    mapping(uint256 => Epoch) public epochs;
    mapping(uint256 => Pool) public pools;
    uint256[] public poolIds;
    mapping(uint256 => mapping(address => UserPosition)) public positions;
    mapping(uint64 => uint256) public entropySeqToEpoch;

    // Chainlink Automation forwarder
    address public automationForwarder;

    // ══════════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ══════════════════════════════════════════════════════════════════════════════

    event PoolCreated(uint256 indexed poolId, address indexed creator);
    event Deposited(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed poolId, uint256 amount);
    event DrawStarted(uint256 indexed epochId);
    event RandomnessRequested(uint256 indexed epochId, uint64 sequence);
    event RandomnessReceived(uint256 indexed epochId, bytes32 randomness);
    event WinnerSelected(uint256 indexed epochId, uint256 indexed winningPoolId, uint256 prize);
    event PrizeClaimed(address indexed user, uint256 indexed poolId, uint256 amount);

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

    // ══════════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ══════════════════════════════════════════════════════════════════════════════

    constructor(
        IERC20 depositToken_,
        IERC4626 yieldVault_,
        IEntropyV2 entropy_,
        uint64 drawIntervalSeconds,
        uint256 maxPools_
    ) Ownable(msg.sender) {
        require(address(depositToken_) != address(0), "Invalid deposit token");
        require(address(yieldVault_) != address(0), "Invalid yield vault");
        require(address(entropy_) != address(0), "Invalid entropy");
        require(drawIntervalSeconds > 0, "Invalid draw interval");

        depositToken = depositToken_;
        yieldVault = yieldVault_;
        entropy = entropy_;
        drawInterval = drawIntervalSeconds;
        maxPools = maxPools_;

        require(yieldVault_.asset() == address(depositToken_), "Asset mismatch");

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

        // Create default pool so users can deposit immediately
        _createPool(msg.sender);

        // Approve yield vault for deposits
        depositToken_.approve(address(yieldVault_), type(uint256).max);
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // ADMIN
    // ══════════════════════════════════════════════════════════════════════════════

    function setAutomationForwarder(address forwarder) external onlyOwner {
        automationForwarder = forwarder;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // VIEWS
    // ══════════════════════════════════════════════════════════════════════════════

    function poolIdsLength() external view returns (uint256) {
        return poolIds.length;
    }

    function totalAssets() public view returns (uint256) {
        uint256 shares = yieldVault.balanceOf(address(this));
        return yieldVault.convertToAssets(shares);
    }

    function currentPrizePool() public view returns (uint256) {
        uint256 assets = totalAssets();
        uint256 liabilities = totalDeposits + totalUnclaimedPrizes;
        return assets > liabilities ? assets - liabilities : 0;
    }

    function getEpoch(uint256 epochId) external view returns (Epoch memory) {
        return epochs[epochId];
    }

    function getCurrentEpoch() external view returns (Epoch memory) {
        return epochs[currentEpochId];
    }

    function getUserPosition(uint256 poolId, address user) external view returns (uint256 deposited, uint256 claimable) {
        UserPosition storage pos = positions[poolId][user];
        deposited = pos.deposits;
        claimable = _pendingPrize(poolId, user);
    }

    function getTimeUntilDraw() external view returns (uint256) {
        Epoch storage e = epochs[currentEpochId];
        if (block.timestamp >= e.end) return 0;
        return e.end - block.timestamp;
    }

    function _pendingPrize(uint256 poolId, address user) internal view returns (uint256) {
        UserPosition storage pos = positions[poolId][user];
        Pool storage pool = pools[poolId];
        if (!pool.exists) return 0;
        uint256 deltaIndex = pool.rewardIndex - pos.rewardIndexPaid;
        return pos.pendingPrize + (pos.deposits * deltaIndex) / 1e18;
    }

    // ══════════════════════════════════════════════════════════════════════════════
    // USER ACTIONS
    // ══════════════════════════════════════════════════════════════════════════════

    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        depositTo(amount, 1, msg.sender); // Default pool ID = 1
    }

    function depositTo(uint256 amount, uint256 poolId, address recipient) public nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (!pools[poolId].exists) revert PoolDoesNotExist();

        _updateUserRewards(poolId, recipient);

        depositToken.safeTransferFrom(msg.sender, address(this), amount);
        yieldVault.deposit(amount, address(this));

        UserPosition storage pos = positions[poolId][recipient];
        pos.deposits += amount;

        Pool storage pool = pools[poolId];
        pool.totalDeposits += amount;
        totalDeposits += amount;

        _updatePoolBalance(poolId, pool.totalDeposits);

        emit Deposited(recipient, poolId, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        withdrawFrom(amount, 1); // Default pool ID = 1
    }

    function withdrawFrom(uint256 amount, uint256 poolId) public nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!pools[poolId].exists) revert PoolDoesNotExist();

        _updateUserRewards(poolId, msg.sender);

        UserPosition storage pos = positions[poolId][msg.sender];
        if (pos.deposits < amount) revert InsufficientBalance();

        pos.deposits -= amount;

        Pool storage pool = pools[poolId];
        pool.totalDeposits -= amount;
        totalDeposits -= amount;

        _updatePoolBalance(poolId, pool.totalDeposits);

        yieldVault.withdraw(amount, msg.sender, address(this));

        emit Withdrawn(msg.sender, poolId, amount);
    }

    function claimPrize() external nonReentrant returns (uint256) {
        return claimPrizeFrom(1); // Default pool ID = 1
    }

    function claimPrizeFrom(uint256 poolId) public nonReentrant returns (uint256 prize) {
        if (!pools[poolId].exists) revert PoolDoesNotExist();

        _updateUserRewards(poolId, msg.sender);

        UserPosition storage pos = positions[poolId][msg.sender];
        prize = pos.pendingPrize;
        if (prize == 0) return 0;

        pos.pendingPrize = 0;
        totalUnclaimedPrizes -= prize;

        yieldVault.withdraw(prize, msg.sender, address(this));

        emit PrizeClaimed(msg.sender, poolId, prize);
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
        _requestRandomnessWithPayment();
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

        // For automation, we assume ETH is pre-funded to contract
        uint256 fee = entropy.getFeeV2();
        require(address(this).balance >= fee, "Insufficient ETH for randomness");

        uint64 seq = entropy.requestV2{value: fee}();
        e.entropySequence = seq;
        e.status = EpochStatus.RandomnessRequested;
        entropySeqToEpoch[seq] = currentEpochId;

        emit RandomnessRequested(currentEpochId, seq);
    }

    function _requestRandomnessWithPayment() internal {
        Epoch storage e = epochs[currentEpochId];
        if (e.status != EpochStatus.Closed) revert InvalidEpochState();

        uint256 fee = entropy.getFeeV2();
        require(msg.value >= fee, "Insufficient fee");

        uint64 seq = entropy.requestV2{value: fee}();
        e.entropySequence = seq;
        e.status = EpochStatus.RandomnessRequested;
        entropySeqToEpoch[seq] = currentEpochId;

        emit RandomnessRequested(currentEpochId, seq);

        if (msg.value > fee) {
            (bool ok,) = msg.sender.call{value: msg.value - fee}("");
            require(ok, "Refund failed");
        }
    }

    /// @notice Entropy callback - MUST NOT REVERT
    function entropyCallback(uint64 sequenceNumber, address, bytes32 randomNumber) external {
        if (msg.sender != address(entropy)) return;

        uint256 epochId = entropySeqToEpoch[sequenceNumber];
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

        uint256 prize = currentPrizePool();
        uint256 winningPoolId = _selectWinner(e.randomness);

        if (prize > 0 && winningPoolId != 0) {
            Pool storage pool = pools[winningPoolId];
            if (pool.totalDeposits > 0) {
                pool.rewardIndex += (prize * 1e18) / pool.totalDeposits;
                totalUnclaimedPrizes += prize;
            }
        }

        e.prize = prize;
        e.winningPoolId = winningPoolId;

        emit WinnerSelected(currentEpochId, winningPoolId, prize);

        // Start next epoch
        uint256 nextEpochId = currentEpochId + 1;
        uint64 nextStart = e.end;

        currentEpochId = nextEpochId;
        epochs[nextEpochId] = Epoch({
            start: nextStart,
            end: nextStart + drawInterval,
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

    function _updateUserRewards(uint256 poolId, address user) internal {
        Pool storage pool = pools[poolId];
        UserPosition storage pos = positions[poolId][user];

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
            uint256 w = pools[poolIds[i]].lastBalance;
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

    receive() external payable {}
}
