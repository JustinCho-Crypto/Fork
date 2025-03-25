// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "forge-std/console2.sol";
import "test/helpers/IntegrationTest.sol";

contract TestIntegrationWithdrawAgg is IntegrationTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using TestMarketLib for TestMarket;

    struct WithdrawAggTest {
        uint256 supplied;
        uint256 withdrawn;
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

    function testShouldWithdrawAggPoolOnly(uint256 seed, uint256 amount, address onBehalf, address receiver) public {
        WithdrawAggTest memory test;

        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        TestMarket storage market = testMarkets[_randomUnderlying(seed)];
        vm.assume(receiver != market.aToken);

        _prepareOnBehalf(onBehalf);

        test.supplied = _boundSupply(market, amount);
        uint256 promoted = _promoteSupply(promoter1, market, test.supplied.percentMul(50_00)); // <= 50% peer-to-peer because market is not guaranteed to be borrowable.
        amount = test.supplied - promoted;
        
        console2.log("(Before)total supplied: ", test.supplied);
        console2.log("(Before)promoted: ", promoted);
        console2.log("(Before)amount: ", amount);

        test.balanceBefore = ERC20(market.underlying).balanceOf(receiver);
        test.morphoSupplyBefore = market.supplyOf(address(morpho));

        user.approve(market.underlying, test.supplied);
        user.supplyAgg(market.underlying, test.supplied, onBehalf);

        vm.expectEmit(true, true, true, false, address(morpho));
        emit Events.WithdrawnAgg(address(user), onBehalf, receiver, market.underlying, amount, 0, 0);

        test.withdrawn = user.withdrawAgg(market.underlying, amount, onBehalf, receiver);

        test.morphoMarket = morpho.market(market.underlying);
        test.indexes = morpho.updatedIndexes(market.underlying);
        test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);
        test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);
        test.scaledCollateral = morpho.scaledCollateralBalance(market.underlying, onBehalf);
        test.collaterals = morpho.userCollaterals(onBehalf);
        test.borrows = morpho.userBorrows(onBehalf);
        uint256 p2pSupply = test.scaledP2PSupply.rayMul(test.indexes.supply.p2pIndex);
        uint256 remaining = test.supplied - test.withdrawn;

        console2.log("(After)total supplied: ", test.scaledP2PSupply + test.scaledPoolSupply);
        console2.log("(After)promoted: ", test.scaledP2PSupply);
        console2.log("(After)amount: ", test.scaledPoolSupply);
        console2.log("(After)collateral: ", test.scaledCollateral);

        // Assert balances on Morpho.
        assertEq(test.scaledPoolSupply, 0, "scaledPoolSupply != 0");
        assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
        assertApproxLeAbs(test.withdrawn, amount, 1, "withdrawn != amount");
        assertApproxLeAbs(p2pSupply, promoted, 2, "p2pSupply != promoted");

        assertEq(test.collaterals.length, 0, "collaterals.length");
        assertEq(test.borrows.length, 0, "borrows.length");

        assertApproxLeAbs(morpho.supplyBalance(market.underlying, onBehalf), remaining, 2, "supply != remaining");
        assertEq(morpho.collateralBalance(market.underlying, onBehalf), 0, "collateral != 0");

        // Assert Morpho's position on pool.
        assertApproxEqAbs(
            market.supplyOf(address(morpho)), test.morphoSupplyBefore, 2, "morphoSupply != morphoSupplyBefore"
        );
        assertApproxEqAbs(market.variableBorrowOf(address(morpho)), 0, 2, "morphoVariableBorrow != 0");

        // Assert receiver's underlying balance.
        assertApproxEqAbs(
            ERC20(market.underlying).balanceOf(receiver),
            test.balanceBefore + amount,
            1,
            "balanceAfter - balanceBefore != amount"
        );

        // Assert Morpho's market state.
        assertEq(test.morphoMarket.deltas.supply.scaledDelta, 0, "scaledSupplyDelta != 0");
        assertEq(
            test.morphoMarket.deltas.supply.scaledP2PTotal,
            test.scaledP2PSupply,
            "scaledTotalSupplyP2P != scaledP2PSupply"
        );
        assertEq(test.morphoMarket.deltas.borrow.scaledDelta, 0, "scaledBorrowDelta != 0");
        assertEq(
            test.morphoMarket.deltas.borrow.scaledP2PTotal,
            test.scaledP2PSupply,
            "scaledTotalBorrowP2P != scaledP2PSupply"
        );
        assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
    }

    function testShouldWithdrawAggAllSupply(uint256 seed, uint256 amount, address onBehalf, address receiver) public {
        WithdrawAggTest memory test;

        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        TestMarket storage market = testMarkets[_randomUnderlying(seed)];
        vm.assume(receiver != market.aToken);

        _prepareOnBehalf(onBehalf);

        test.supplied = _boundSupply(market, amount);
        test.supplied = bound(test.supplied, 0, market.liquidity()); // Because >= 50% will get borrowed from the pool.
        uint256 promoted = _promoteSupply(promoter1, market, test.supplied.percentMul(50_00)); // <= 50% peer-to-peer because market is not guaranteed to be borrowable.
        amount = bound(amount, test.supplied + 1, type(uint256).max);

        test.balanceBefore = ERC20(market.underlying).balanceOf(receiver);
        test.morphoSupplyBefore = market.supplyOf(address(morpho));

        console2.log("(Before func2)total supplied: ", test.supplied);
        console2.log("(Before func2)promoted: ", promoted);
        console2.log("(Before func2)amount: ", amount);

        user.approve(market.underlying, test.supplied);
        user.supplyAgg(market.underlying, test.supplied, onBehalf);

        if (promoted > 0) {
            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.BorrowPositionUpdated(address(promoter1), market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);
        }

        vm.expectEmit(true, true, true, false, address(morpho));
        emit Events.WithdrawnAgg(address(user), onBehalf, receiver, market.underlying, test.supplied, 0, 0);

        test.withdrawn = user.withdrawAgg(market.underlying, amount, onBehalf, receiver);

        test.morphoMarket = morpho.market(market.underlying);
        test.indexes = morpho.updatedIndexes(market.underlying);
        test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);
        test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);
        test.scaledCollateral = morpho.scaledCollateralBalance(market.underlying, onBehalf);
        test.collaterals = morpho.userCollaterals(onBehalf);
        test.borrows = morpho.userBorrows(onBehalf);

        console2.log("(After func2)total supplied: ", test.scaledP2PSupply + test.scaledPoolSupply);
        console2.log("(After func2)promoted: ", test.scaledP2PSupply);
        console2.log("(After func2)amount: ", test.scaledPoolSupply);
        console2.log("(After func2)collateral: ", test.scaledCollateral);

        // Assert balances on Morpho.
        assertEq(test.scaledP2PSupply, 0, "scaledP2PSupply != 0");
        assertEq(test.scaledPoolSupply, 0, "scaledPoolSupply != 0");
        assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
        assertApproxEqAbs(test.withdrawn, test.supplied, 3, "withdrawn != supplied");
        assertApproxEqAbs(
            morpho.scaledP2PBorrowBalance(market.underlying, address(promoter1)), 0, 2, "promoterScaledP2PBorrow != 0"
        );

        assertEq(test.collaterals.length, 0, "collaterals.length");
        assertEq(test.borrows.length, 0, "borrows.length");

        // Assert Morpho getters.
        assertEq(morpho.supplyBalance(market.underlying, onBehalf), 0, "supply != 0");
        assertEq(morpho.collateralBalance(market.underlying, onBehalf), 0, "collateral != 0");
        assertApproxEqAbs(
            morpho.borrowBalance(market.underlying, address(promoter1)), promoted, 3, "promoterBorrow != promoted"
        );

        // Assert Morpho's position on pool.
        assertApproxEqAbs(
            market.supplyOf(address(morpho)), test.morphoSupplyBefore, 2, "morphoSupply != morphoSupplyBefore"
        );
        assertApproxEqAbs(market.variableBorrowOf(address(morpho)), promoted, 3, "morphoVariableBorrow != promoted");

        // Assert receiver's underlying balance.
        assertApproxLeAbs(
            ERC20(market.underlying).balanceOf(receiver),
            test.balanceBefore + test.withdrawn,
            2,
            "balanceAfter != balanceBefore + withdrawn"
        );

        // Assert Morpho's market state.
        assertEq(test.morphoMarket.deltas.supply.scaledDelta, 0, "scaledSupplyDelta != 0");
        assertApproxEqAbs(test.morphoMarket.deltas.supply.scaledP2PTotal, 0, 2, "scaledTotalSupplyP2P != 0");
        assertEq(test.morphoMarket.deltas.borrow.scaledDelta, 0, "scaledBorrowDelta != 0");
        assertApproxEqAbs(test.morphoMarket.deltas.borrow.scaledP2PTotal, 0, 2, "scaledTotalBorrowP2P != 0");
        assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
    }

}
