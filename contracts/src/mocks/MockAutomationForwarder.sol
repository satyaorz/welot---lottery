// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @notice Minimal mock automation forwarder for local/testnet testing.
/// Caller can invoke `run` which will forward the `performData` to the target's `performUpkeep`.
contract MockAutomationForwarder {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    /// @notice Forward a performUpkeep call to a target contract.
    /// @param target The AutomationCompatible target (e.g., `WelotVault`)
    /// @param performData ABI-encoded performData expected by the target
    function run(address target, bytes calldata performData) external {
        // Forward the call as this contract so targets that check `msg.sender == automationForwarder`
        // will accept it. No access control here for tests.
        (bool ok, bytes memory ret) = target.call(abi.encodeWithSelector(bytes4(keccak256("performUpkeep(bytes)")), performData));
        require(ok, string(ret));
    }

    /// @notice Helper to let owner withdraw stray ETH
    function withdraw(address to, uint256 amount) external {
        require(msg.sender == owner, "only owner");
        payable(to).transfer(amount);
    }

    receive() external payable {}
}
