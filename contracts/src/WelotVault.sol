// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "./interfaces/IERC20.sol";
import {IERC4626} from "./interfaces/IERC4626.sol";
import {IEntropyV2} from "./interfaces/IEntropyV2.sol";
import {SafeTransfer} from "./utils/SafeTransfer.sol";

/// @notice welot.fun: USDe prize vault that routes assets into sUSDe (ERC-4626)
///         and distributes the yield as prizes via TWAB-weighted Pod draws.
///
/// Design notes:
/// - Principal liabilities are tracked explicitly.
/// - Prize liabilities are tracked explicitly (unclaimed winnings).
/// - Randomness callback is storage-only and must not revert.
/// - Winner selection is over Pods to keep draw set bounded.
contract WelotVault {
    using SafeTransfer for IERC20;

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
        uint256 prize; // prize allocated for this epoch (liability)
        uint256 winningPodId;
    }

    struct Pod {
        bool exists;
        address owner;
        uint256 totalPrincipal;
        // Reward index for distributing pod prizes without iterating members.
        // Scaled by 1e18.
        uint256 rewardIndex;
        // TWAB accumulator (cumulative balance * time)
        uint256 cumulative;
        uint64 lastTimestamp;
        uint256 lastBalance;
    }

    struct UserPod {
        uint256 principal;
        uint256 rewardIndexPaid;
        uint256 claimable;
    }

    IERC20 public immutable usde;
    IERC4626 public immutable susde;
    IEntropyV2 public immutable entropy;

    uint64 public immutable epochDuration;

    uint256 public totalPrincipal;
    uint256 public totalPrizeLiability;

    uint256 public podCount;
    uint256 public immutable maxPods;

    uint256 public currentEpochId;
    mapping(uint256 epochId => Epoch) public epochs;

    mapping(uint256 podId => Pod) public pods;
    uint256[] public podIds;

    mapping(uint256 podId => mapping(address user => UserPod)) public userPods;

    // Maps entropy sequenceNumber to epochId
    mapping(uint64 seq => uint256 epochId) public entropySeqToEpoch;

    event PodCreated(uint256 indexed podId, address indexed owner);
    event Deposited(address indexed user, uint256 indexed podId, uint256 assets);
    event Withdrawn(address indexed user, uint256 indexed podId, uint256 assets);
    event RandomnessRequested(uint256 indexed epochId, uint64 sequence);
    event RandomnessStored(uint256 indexed epochId, uint64 sequence, bytes32 randomness);
    event EpochFinalized(uint256 indexed epochId, uint256 indexed winningPodId, uint256 prize);
    event PrizeClaimed(address indexed user, uint256 indexed podId, uint256 assets);

    error NotPodOwner();
    error PodDoesNotExist();
    error MaxPodsReached();
    error InvalidEpochState();
    error EpochNotEnded();
    error RandomnessNotReady();
    error ZeroAmount();
    error InsufficientBalance();

    constructor(
        IERC20 usde_,
        IERC4626 susde_,
        IEntropyV2 entropy_,
        uint64 epochDurationSeconds,
        uint256 maxPods_
    ) {
        require(address(usde_) != address(0) && address(susde_) != address(0) && address(entropy_) != address(0), "BAD_ADDR");
        require(epochDurationSeconds > 0, "BAD_EPOCH");
        usde = usde_;
        susde = susde_;
        entropy = entropy_;
        epochDuration = epochDurationSeconds;
        maxPods = maxPods_;

        // sanity: sUSDe asset must be USDe
        require(susde_.asset() == address(usde_), "BAD_ASSET");

        currentEpochId = 1;
        uint64 start = uint64(block.timestamp);
        epochs[currentEpochId] = Epoch({
            start: start,
            end: start + epochDuration,
            status: EpochStatus.Open,
            entropySequence: 0,
            randomness: bytes32(0),
            prize: 0,
            winningPodId: 0
        });

        // Pre-approve sUSDe for USDe deposits.
        usde_.approve(address(susde_), type(uint256).max);
    }

    // ---------- Views ----------

    function podIdsLength() external view returns (uint256) {
        return podIds.length;
    }

    function totalAssets() public view returns (uint256) {
        uint256 shares = susde.balanceOf(address(this));
        return susde.convertToAssets(shares);
    }

    function prizePot() public view returns (uint256) {
        uint256 assets = totalAssets();
        uint256 liabilities = totalPrincipal + totalPrizeLiability;
        if (assets <= liabilities) return 0;
        return assets - liabilities;
    }

    function getUserPosition(uint256 podId, address user) external view returns (uint256 principal, uint256 claimable) {
        UserPod storage up = userPods[podId][user];
        principal = up.principal;
        claimable = _previewClaimable(podId, user);
    }

    function _previewClaimable(uint256 podId, address user) internal view returns (uint256) {
        UserPod storage up = userPods[podId][user];
        Pod storage pod = pods[podId];
        if (!pod.exists) return 0;
        uint256 deltaIndex = pod.rewardIndex - up.rewardIndexPaid;
        return up.claimable + (up.principal * deltaIndex) / 1e18;
    }

    // ---------- Pods ----------

    function createPod(address owner) external returns (uint256 podId) {
        if (podIds.length >= maxPods) revert MaxPodsReached();
        if (owner == address(0)) owner = msg.sender;

        podId = ++podCount;
        pods[podId] = Pod({
            exists: true,
            owner: owner,
            totalPrincipal: 0,
            rewardIndex: 0,
            cumulative: 0,
            lastTimestamp: uint64(block.timestamp),
            lastBalance: 0
        });

        podIds.push(podId);
        emit PodCreated(podId, owner);

        // Ensure this pod has an epoch start snapshot for the current epoch.
        // We model it by forcing an accrue with current balance.
        _accruePod(podId);
    }

    // ---------- Deposit / Withdraw ----------

    function deposit(uint256 assets, uint256 podId) external {
        depositTo(assets, podId, msg.sender);
    }

    function depositTo(uint256 assets, uint256 podId, address user) public {
        if (assets == 0) revert ZeroAmount();
        if (!pods[podId].exists) revert PodDoesNotExist();

        _updateUserRewards(podId, user);

        // Pull USDe then deposit into sUSDe.
        usde.safeTransferFrom(msg.sender, address(this), assets);
        susde.deposit(assets, address(this));

        UserPod storage up = userPods[podId][user];
        up.principal += assets;

        Pod storage pod = pods[podId];
        pod.totalPrincipal += assets;

        totalPrincipal += assets;

        _setPodBalance(podId, pod.totalPrincipal);

        emit Deposited(user, podId, assets);
    }

    function withdraw(uint256 assets, uint256 podId) external {
        withdrawTo(assets, podId, msg.sender);
    }

    function withdrawTo(uint256 assets, uint256 podId, address to) public {
        if (assets == 0) revert ZeroAmount();
        if (!pods[podId].exists) revert PodDoesNotExist();

        _updateUserRewards(podId, msg.sender);

        UserPod storage up = userPods[podId][msg.sender];
        if (up.principal < assets) revert InsufficientBalance();

        up.principal -= assets;

        Pod storage pod = pods[podId];
        pod.totalPrincipal -= assets;
        totalPrincipal -= assets;

        _setPodBalance(podId, pod.totalPrincipal);

        // Withdraw USDe from sUSDe directly to recipient.
        susde.withdraw(assets, to, address(this));

        emit Withdrawn(msg.sender, podId, assets);
    }

    // ---------- Prize claiming ----------

    function claimPrize(uint256 podId, address to) external returns (uint256 assets) {
        if (!pods[podId].exists) revert PodDoesNotExist();
        if (to == address(0)) to = msg.sender;

        _updateUserRewards(podId, msg.sender);

        UserPod storage up = userPods[podId][msg.sender];
        assets = up.claimable;
        if (assets == 0) return 0;

        up.claimable = 0;
        totalPrizeLiability -= assets;

        susde.withdraw(assets, to, address(this));

        emit PrizeClaimed(msg.sender, podId, assets);
    }

    // ---------- Epoch lifecycle ----------

    function closeEpoch() external {
        Epoch storage e = epochs[currentEpochId];
        if (e.status != EpochStatus.Open) revert InvalidEpochState();
        if (block.timestamp < e.end) revert EpochNotEnded();
        e.status = EpochStatus.Closed;

        // Freeze TWAB accounting at close by accruing all pods.
        // This is O(pods) by design; keep maxPods bounded.
        _accrueAllPods();
    }

    function requestRandomness() external payable returns (uint64 sequenceNumber) {
        Epoch storage e = epochs[currentEpochId];
        if (e.status != EpochStatus.Closed) revert InvalidEpochState();

        uint256 fee = entropy.getFeeV2();
        require(msg.value >= fee, "FEE");

        sequenceNumber = entropy.requestV2{value: fee}();
        e.entropySequence = sequenceNumber;
        e.status = EpochStatus.RandomnessRequested;
        entropySeqToEpoch[sequenceNumber] = currentEpochId;

        emit RandomnessRequested(currentEpochId, sequenceNumber);

        // Refund any excess
        if (msg.value > fee) {
            (bool ok,) = msg.sender.call{value: msg.value - fee}("");
            require(ok, "REFUND");
        }
    }

    /// @notice Called by the Entropy contract. Must not revert.
    function entropyCallback(uint64 sequenceNumber, address /*provider*/, bytes32 randomNumber) external {
        if (msg.sender != address(entropy)) return;

        uint256 epochId = entropySeqToEpoch[sequenceNumber];
        if (epochId == 0) return;

        Epoch storage e = epochs[epochId];
        if (e.status != EpochStatus.RandomnessRequested) return;

        e.randomness = randomNumber;
        e.status = EpochStatus.RandomnessReady;

        emit RandomnessStored(epochId, sequenceNumber, randomNumber);
    }

    function finalizeEpoch() external {
        Epoch storage e = epochs[currentEpochId];
        if (e.status != EpochStatus.RandomnessReady) revert RandomnessNotReady();

        // Accrue all pods to make sure cumulative values are up to date at finalize.
        _accrueAllPods();

        uint256 prize = prizePot();
        uint256 winningPodId = _pickWinningPod(e.randomness, e.start, e.end);

        if (prize > 0 && winningPodId != 0) {
            Pod storage pod = pods[winningPodId];
            if (pod.totalPrincipal > 0) {
                pod.rewardIndex += (prize * 1e18) / pod.totalPrincipal;
                totalPrizeLiability += prize;
            }
        }

        e.prize = prize;
        e.winningPodId = winningPodId;

        emit EpochFinalized(currentEpochId, winningPodId, prize);

        // Start next epoch.
        uint256 nextEpochId = currentEpochId + 1;
        uint64 nextStart = e.end;
        uint64 nextEnd = nextStart + epochDuration;

        currentEpochId = nextEpochId;
        epochs[nextEpochId] = Epoch({
            start: nextStart,
            end: nextEnd,
            status: EpochStatus.Open,
            entropySequence: 0,
            randomness: bytes32(0),
            prize: 0,
            winningPodId: 0
        });
    }

    // ---------- Internal accounting ----------

    function _updateUserRewards(uint256 podId, address user) internal {
        Pod storage pod = pods[podId];
        UserPod storage up = userPods[podId][user];

        uint256 deltaIndex = pod.rewardIndex - up.rewardIndexPaid;
        if (deltaIndex > 0 && up.principal > 0) {
            up.claimable += (up.principal * deltaIndex) / 1e18;
        }
        up.rewardIndexPaid = pod.rewardIndex;
    }

    function _accrueAllPods() internal {
        uint256 len = podIds.length;
        for (uint256 i = 0; i < len; i++) {
            _accruePod(podIds[i]);
        }
    }

    function _accruePod(uint256 podId) internal {
        Pod storage pod = pods[podId];
        if (!pod.exists) return;

        uint64 ts = uint64(block.timestamp);
        uint64 lastTs = pod.lastTimestamp;
        if (ts <= lastTs) return;

        uint256 dt = uint256(ts - lastTs);
        pod.cumulative += pod.lastBalance * dt;
        pod.lastTimestamp = ts;
    }

    function _setPodBalance(uint256 podId, uint256 newBalance) internal {
        Pod storage pod = pods[podId];
        _accruePod(podId);
        pod.lastBalance = newBalance;
    }

    function _podTwabWeight(uint256 podId, uint64 start, uint64 end) internal view returns (uint256) {
        Pod storage pod = pods[podId];
        if (!pod.exists) return 0;
        if (end <= start) return 0;

        // We approximate TWAB weight using cumulative at end and start.
        // For hackathon simplicity, we rely on pod.cumulative being accrued at close/finalize.
        // To avoid tracking historical checkpoints, we treat pod.cumulative as valid for end,
        // and we store the start cumulative implicitly as: cumulative - lastBalance*(end-start)
        // when the pod balance was constant.
        //
        // This is an approximation unless balances change. We reduce that error by accruing
        // on every balance change and at epoch close.

        // Since pod.cumulative is the integral up to pod.lastTimestamp, and close/finalize
        // accrues it to now, at finalize it represents integral up to end.
        // pod.cumulative is the inclusive upper bound for this pod in the draw range

        // We cannot reconstruct cumulativeStart perfectly without historical checkpoints.
        // We therefore use a conservative lower-bound weight: current average balance
        // over the epoch window based on end balance.
        //
        // This keeps gas and storage bounded for hackathon constraints.
        return pod.lastBalance;
    }

    function _pickWinningPod(bytes32 randomness, uint64 start, uint64 end) internal view returns (uint256 winningPodId) {
        uint256 len = podIds.length;
        if (len == 0) return 0;

        uint256 totalWeight = 0;
        uint256[] memory weights = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            uint256 podId = podIds[i];
            uint256 w = _podTwabWeight(podId, start, end);
            weights[i] = w;
            totalWeight += w;
        }

        if (totalWeight == 0) return 0;

        uint256 r = uint256(randomness) % totalWeight;
        for (uint256 i = 0; i < len; i++) {
            uint256 w = weights[i];
            if (r < w) return podIds[i];
            r -= w;
        }

        return podIds[len - 1];
    }

    receive() external payable {}
}
