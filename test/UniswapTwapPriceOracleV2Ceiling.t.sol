pragma solidity 0.6.12;

import {Vm} from "forge-std/Vm.sol";
import "ds-test/test.sol";
import "src/UniswapTwapPriceOracleV2Ceiling.sol";
import "src/IUniswapV2Pair.sol";
import "src/IERC20.sol";

contract UniswapTwapPriceOracleV2CeilingTests is DSTest {
    Vm internal constant vm = Vm(HEVM_ADDRESS);
    address inv = 0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68;
    address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address pair = 0x328dFd0139e26cB0FEF7B0742B49b0fe4325F821;
    IUniswapV2Pair unipair = IUniswapV2Pair(pair);
    address gov = address(0xa);
    address guardian = address(0xb);
    address wethHolder = 0x2fEb1512183545f48f6b9C5b4EbfCaF49CfCa6F3;
    UniswapTwapPriceOracleV2Ceiling oracle;

    function setUp() public {
        oracle = new UniswapTwapPriceOracleV2Ceiling(
            15 minutes,
            20000, //Ceiling can be set 200% higher than current price
            5000, // Ceiling must be set 50% higher than current price
            18, //Inv decimals
            pair,
            gov,
            guardian
        );
    }

    function testUpdate_Succeed_When_TWAPTimePassed() public {
        vm.warp(block.timestamp + 15 minutes + 1);
        assertTrue(oracle.update());
    }

    function test_Update_IsFalse_When_WithinTWAPTime() public {
        vm.startPrank(wethHolder);
        vm.warp(block.timestamp + 15 minutes + 1);
        assertTrue(oracle.update());
        swapExactIn(1 ether, weth, unipair, wethHolder);

        assert(oracle.update() == true);
        swapExactIn(1 ether, weth, unipair, wethHolder);
        assert(oracle.update() == false);
        vm.warp(block.timestamp + oracle.MIN_TWAP_TIME() - 1);
        swapExactIn(1 ether, weth, unipair, wethHolder);
        assert(oracle.update() == false);
        vm.warp(block.timestamp + 2);
        swapExactIn(1 ether, weth, unipair, wethHolder);
        assert(oracle.update() == true);
    }

    function test_Price_HasChanged_When_UpdateIsCalled() public {
        vm.warp(block.timestamp + 15 minutes + 1);
        oracle.update();
        vm.startPrank(wethHolder);
        uint priceBefore = oracle.price();

        swapExactIn(1 ether, weth, unipair, wethHolder);
        vm.warp(block.timestamp + oracle.MIN_TWAP_TIME() +1);
        assertTrue(oracle.update());

        assert(priceBefore < oracle.price());
    }

    function test_Price_EqualCeiling_When_PriceHigerThanCeiling() public {
        vm.warp(block.timestamp + 15 minutes + 1);
        oracle.update();
        vm.startPrank(guardian);
        oracle.setPriceCeiling(oracle.price()*2);
        vm.stopPrank();
        vm.startPrank(wethHolder);

        swapExactIn(2000 ether, weth, unipair, wethHolder);
        vm.warp(block.timestamp + oracle.MIN_TWAP_TIME() +1);
        assertTrue(oracle.update());

        assertEq(oracle.priceCeiling(), oracle.price());
       
    }

    function test_setPriceCeiling_Succeed_When_SetByGuardian() public{
        vm.startPrank(guardian);
        vm.warp(block.timestamp + 15 minutes + 1);
        oracle.update();
        uint price = oracle.price();
        uint priceCeilingBefore = oracle.priceCeiling();

        oracle.setPriceCeiling(price*2);

        assertEq(price*2, oracle.priceCeiling());
        assert(oracle.priceCeiling() != priceCeilingBefore);
    }

    function testFail_setPriceCeiling_Revert_When_SetAboveBounds() public{
        vm.startPrank(guardian);
        vm.warp(block.timestamp + 15 minutes + 1);
        oracle.update();

        oracle.setPriceCeiling(type(uint).max);
    }

    function testFail_setPriceCeiling_Revert_When_SetBelowBounds() public{
        vm.startPrank(guardian);
        vm.warp(block.timestamp + 15 minutes + 1);
        oracle.update();

        oracle.setPriceCeiling(oracle.price());
    }

    function test_setMaxBPCeiling_Succeed_When_SetByGovernance() public {
        vm.startPrank(gov);

        oracle.setMaxBPCeiling(10000);
    }


    function testFail_setMaxBPCeiling_Fail_When_SetBelowMinBPCeiling() public {
        vm.startPrank(gov);

        oracle.setMaxBPCeiling(oracle.minBPCeiling()-1);
    }

    function test_setMinBPCeiling_Succeed_When_SetByGovernance() public {
        vm.startPrank(gov);

        oracle.setMinBPCeiling(10000);
    }

    function testFail_setMinBPCeiling_Fail_When_SetAboveMaxBPCeiling() public {
        vm.startPrank(gov);

        oracle.setMinBPCeiling(oracle.maxBPCeiling()+1);
    }

    // ************************
    // * ACCESS CONTROL TESTS *
    // ************************
    function testFail_setPriceCeiling_Fail_When_CalledByNonGuardian() public{
        vm.warp(block.timestamp + 15 minutes + 1);
        oracle.update();
        vm.startPrank(wethHolder);
        oracle.setPriceCeiling(oracle.price()*2);
    }

    function testFail_setGuardian_Fail_When_CalledByNonGovernance() public{
        vm.startPrank(wethHolder);
        oracle.setGuardian(guardian);
    }

    function testFail_setMaxBPCeiling_Fail_When_CalledByNonGovernance() public{
        vm.startPrank(wethHolder);
        oracle.setMaxBPCeiling(30000);
    }

    function testFail_setMinBPCeiling_Fail_When_CalledByNonGovernance() public{
        vm.startPrank(wethHolder);
        oracle.setMinBPCeiling(10000);
    }

    // ********************
    // * HELPER FUNCTIONS *
    // ********************
    function getAmountOut(uint amountIn, address tokenIn, IUniswapV2Pair pair) public view returns (uint) {
        uint reserveIn;
        uint reserveOut;
        (uint112 token0Reserves, uint112 token1Reserves,) = pair.getReserves();
        if(pair.token0() == tokenIn){
            reserveIn = uint(token0Reserves);
            reserveOut = uint(token1Reserves);
        } else {
            reserveIn = uint(token1Reserves);
            reserveOut = uint(token0Reserves);
        }
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 1000 + amountInWithFee;
        return numerator / denominator;
    }

    function swapExactIn(uint amountIn, address tokenIn, IUniswapV2Pair pair, address to) public returns (uint){
        uint amountOut = getAmountOut(amountIn, tokenIn, pair);
            IERC20(tokenIn).transfer(address(pair), amountIn);
        if(pair.token0() == tokenIn){
            pair.swap(0, amountOut, to, "");
        } else {
            pair.swap(amountOut, 0, to, "");
        }
        return amountOut;
    }
}
