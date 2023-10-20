// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "forge-std/Test.sol";
import "../../contracts/tokens/EFC.sol";
import "../../contracts/test/MockRewardFarmCallback.sol";
import "../../contracts/test/MockFeeDistributorCallback.sol";

contract EFCTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event CodeBound(address indexed referee, string code, uint256 tokenIdBefore, uint256 tokenIdAfter);
    event CodeRegistered(address indexed referrer, uint256 indexed tokenId, string code);
    EFC public efc;

    function setUp() public {
        efc = new EFC(10, 10, 10, new MockRewardFarmCallback(), new MockFeeDistributorCallback());
        // delegate to self
        vm.prank(address(0));
        efc.delegate(address(0));
        vm.prank(address(1));
        efc.delegate(address(1));
        vm.prank(address(2));
        efc.delegate(address(2));
        vm.prank(address(3));
        efc.delegate(address(3));
        vm.prank(address(4));
        efc.delegate(address(4));
    }

    function test_mintEFCArchitect() public {
        vm.roll(1);
        address[] memory to = new address[](2);
        to[0] = address(1);
        to[1] = address(2);
        for (uint256 i; i < 5; i++) {
            vm.expectEmit(true, true, true, false, address(efc));
            emit Transfer(address(0), address(1), i * 2 + 1);
            vm.expectEmit(true, true, true, false, address(efc));
            emit Transfer(address(0), address(2), i * 2 + 2);
            efc.batchMintArchitect(to);
        }
        vm.expectRevert(abi.encodeWithSelector(IEFC.CapExceeded.selector, 10));
        efc.batchMintArchitect(to);
        assertEqUint(efc.getVotes(address(0)), 0);
        assertEqUint(efc.getVotes(address(1)), 5);
        assertEqUint(efc.getVotes(address(2)), 5);
        vm.roll(2);
        vm.prank(address(1));
        efc.transferFrom(address(1), address(2), 1);
        assertEqUint(efc.getVotes(address(0)), 0);
        assertEqUint(efc.getVotes(address(1)), 4);
        assertEqUint(efc.getVotes(address(2)), 6);

        assertEqUint(efc.getPastVotes(address(0), 1), 0);
        assertEqUint(efc.getPastVotes(address(1), 1), 5);
        assertEqUint(efc.getPastVotes(address(2), 1), 5);
    }

    function test_mintEFCConnector() public {
        address[] memory to = new address[](2);
        to[0] = address(1);
        to[1] = address(2);
        for (uint256 i; i < 5; i++) {
            vm.expectEmit(true, true, true, false, address(efc));
            emit Transfer(address(0), address(1), i * 2 + 1000);
            vm.expectEmit(true, true, true, false, address(efc));
            emit Transfer(address(0), address(2), i * 2 + 1001);
            efc.batchMintConnector(to);
        }
        vm.expectRevert(abi.encodeWithSelector(IEFC.CapExceeded.selector, 10));
        efc.batchMintConnector(to);
        assertEqUint(efc.getVotes(address(0)), 0);
        assertEqUint(efc.getVotes(address(1)), 0);
        assertEqUint(efc.getVotes(address(2)), 0);

        vm.roll(2);
        vm.prank(address(2));
        efc.transferFrom(address(2), address(1), 1001);
        assertEqUint(efc.getVotes(address(0)), 0);
        assertEqUint(efc.getVotes(address(1)), 0);
        assertEqUint(efc.getVotes(address(2)), 0);

        assertEqUint(efc.getPastVotes(address(0), 1), 0);
        assertEqUint(efc.getPastVotes(address(1), 1), 0);
        assertEqUint(efc.getPastVotes(address(2), 1), 0);
    }

    function test_mintEFCMember() public {
        address[] memory to = new address[](2);
        to[0] = address(1);
        to[1] = address(2);
        efc.batchMintConnector(to);
        for (uint256 i; i < 5; i++) {
            vm.expectEmit(true, true, true, false, address(efc));
            emit Transfer(address(0), address(1), i * 2 + 10010);
            vm.expectEmit(true, true, true, false, address(efc));
            emit Transfer(address(0), address(2), i * 2 + 10011);
            vm.prank(address(2));
            efc.batchMintMember(1001, to);
        }
        vm.prank(address(2));
        vm.expectRevert(abi.encodeWithSelector(IEFC.CapExceeded.selector, 10));
        efc.batchMintMember(1001, to);
        assertEqUint(efc.getVotes(address(0)), 0);
        assertEqUint(efc.getVotes(address(1)), 0);
        assertEqUint(efc.getVotes(address(2)), 0);

        vm.roll(2);
        vm.prank(address(1));
        efc.transferFrom(address(1), address(2), 10010);
        assertEqUint(efc.getVotes(address(0)), 0);
        assertEqUint(efc.getVotes(address(1)), 0);
        assertEqUint(efc.getVotes(address(2)), 0);

        assertEqUint(efc.getPastVotes(address(0), 1), 0);
        assertEqUint(efc.getPastVotes(address(1), 1), 0);
        assertEqUint(efc.getPastVotes(address(2), 1), 0);
    }

    function test_code() public {
        string memory code = "test code";
        address[] memory to = new address[](1);
        to[0] = address(1);
        efc.batchMintConnector(to);
        vm.prank(address(1));
        efc.batchMintMember(1000, to);
        vm.prank(address(1));
        vm.expectEmit(true, true, true, false, address(efc));
        emit CodeRegistered(address(1), 10000, code);
        efc.registerCode(10000, code);

        vm.expectRevert(abi.encodeWithSelector(IEFC.NotMemberToken.selector, 1000));
        efc.registerCode(1000, code);

        vm.prank(address(2));
        vm.expectEmit(true, true, false, false, address(efc));
        emit CodeBound(address(2), code, 0, 10000);
        efc.bindCode(code);

        (uint256 memberTokenId, uint256 connectorTokenId) = efc.referrerTokens(address(2));
        assertEqUint(memberTokenId, 10000);
        assertEqUint(connectorTokenId, 1000);
    }

    function test_tokenURI() public {
        address[] memory to = new address[](1);
        to[0] = address(1);
        efc.batchMintArchitect(to);
        efc.batchMintConnector(to);

        vm.prank(address(1));
        address[] memory memberTo = new address[](1);
        memberTo[0] = address(2);
        efc.batchMintMember(1000, memberTo);

        assertEq(efc.tokenURI(1), "");
        assertEq(efc.tokenURI(1000), "");
        assertEq(efc.tokenURI(10000), "");

        efc.setBaseURI("ipfs://type1/");

        assertEq(efc.tokenURI(1), "ipfs://type1/1");
        assertEq(efc.tokenURI(1000), "ipfs://type1/1000");
        assertEq(efc.tokenURI(10000), "ipfs://type1/10000");
    }
}
