// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {MockERC20} from "./MockERC20.sol";

contract MockUSDeFaucet {
    MockERC20 public immutable usde;
    uint256 public immutable amount;

    mapping(address => bool) public claimed;

    error AlreadyClaimed();

    constructor(MockERC20 usde_, uint256 amount_) {
        usde = usde_;
        amount = amount_;
    }

    function claim() external {
        if (claimed[msg.sender]) revert AlreadyClaimed();
        claimed[msg.sender] = true;
        usde.mint(msg.sender, amount);
    }
}
