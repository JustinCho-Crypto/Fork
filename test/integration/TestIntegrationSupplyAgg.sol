// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import "test/helpers/IntegrationTest.sol";

contract TestIntegrationSupplyAgg is IntegrationTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using TestMarketLib for TestMarket;

    struct SupplyAggTest {
        uint256 supplied;
        uint256 balanceBefore;
        uint256 morphoSupplyBefore;
        uint256 scaledP2PSupply;
        uint256 scaledPoolSupply;
        uint256 scaledCollateral;
        address[] collaterals;
        address[] borrows;
        Types.Indexes256 indexes;
        Types.Market morphoMarket;
    }

    function _assertSupplyAgg(TestMarket storage market, uint256 amount, address onBehalf, SupplyAggTest memory test)
        internal
        returns (SupplyAggTest memory)
    {
        test.morphoMarket = morpho.market(market.underlying);
        test.indexes = morpho.updatedIndexes(market.underlying);
        test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);
        test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);
        test.scaledCollateral = morpho.scaledCollateralBalance(market.underlying, onBehalf);
        test.collaterals = morpho.userCollaterals(onBehalf);
        test.borrows = morpho.userBorrows(onBehalf);
        uint256 poolSupply = test.scaledPoolSupply.rayMul(test.indexes.supply.poolIndex);
        uint256 p2pSupply = test.scaledP2PSupply.rayMul(test.indexes.supply.p2pIndex);
        uint256 collateral = test.scaledCollateral.rayMul(test.indexes.supply.poolIndex);

        // Assert balances on Morpho.
        assertEq(test.supplied, amount, "supplied != amount");
        assertApproxEqAbs(poolSupply+p2pSupply, amount, 2, "poolSupply+p2pSupply != amount");

        assertApproxEqAbs(
            morpho.scaledP2PBorrowBalance(market.underlying, address(promoter1)),
            test.scaledP2PSupply,
            1,
            "promoterScaledP2PBorrow != scaledP2PSupply"
        );
        
        assertApproxEqAbs(morpho.supplyBalance(market.underlying, onBehalf), amount, 3, "totalSupply != amount");
        
        console2.log("amount: ", amount);
        console2.log("test.scaledP2PSupply: ", test.scaledP2PSupply.rayMul(test.indexes.supply.p2pIndex));
        console2.log("test.scaledPoolSupply: ", test.scaledPoolSupply.rayMul(test.indexes.supply.poolIndex));
        console2.log("test.scaledCollateral: ", test.scaledCollateral.rayMul(test.indexes.supply.poolIndex));
        // assertEq(test.scaledPoolSupply, 0, "?");
        if(test.scaledPoolSupply > 0) {
            assertGt(test.collaterals.length, 0, "collaterals = 0");
            assertGt(morpho.collateralBalance(market.underlying, onBehalf), 0, "collaterals = 0");
            assertGt(test.scaledCollateral, 0, "scaledCollateral = 0");
        }

        assertApproxEqAbs(p2pSupply, amount - 100, 1, "p2psupply != amount - 100");
        assertApproxEqAbs(poolSupply, 100, 1, "poolSupply != 100");
        assertApproxEqAbs(collateral, 100, 1, "poolSupply != 100");

        // Assert user's underlying balance.
        assertApproxEqAbs(
            test.balanceBefore - user.balanceOf(market.underlying), amount, 1, "balanceBefore - balanceAfter != amount"
        );

        return test;
    }

    function testShouldSupplyAgg(uint256 seed, uint256 amount, address onBehalf) public {
        SupplyAggTest memory test;

        onBehalf = _boundOnBehalf(onBehalf);

        TestMarket storage market = testMarkets[_randomBorrowableInEMode(seed)];
        
        console2.log("market.symbol: ", market.symbol);
        console2.log("market.isBorrowable: ", market.isBorrowable);
        console2.log("market.isInEMode: ", market.isInEMode);
        amount = _boundSupply(market, amount);
        amount = _promoteSupply(promoter1, market, amount) + 100; // 100만큼 Pool에 예치

        test.balanceBefore = user.balanceOf(market.underlying);
        test.morphoSupplyBefore = market.supplyOf(address(morpho));

        user.approve(market.underlying, amount);

        vm.expectEmit(true, true, true, false, address(morpho));
        emit Events.SuppliedAgg(address(user), onBehalf, market.underlying, 0, 0, 0);

        test.supplied = user.supplyAgg(market.underlying, amount, onBehalf, 20); // 100% pool.

        test = _assertSupplyAgg(market, amount, onBehalf, test);

    }
}
