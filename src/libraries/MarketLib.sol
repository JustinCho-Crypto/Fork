// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Types} from "./Types.sol";
import {ThreeHeapOrdering} from "morpho-data-structures/ThreeHeapOrdering.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin-contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

library MarketLib {
    using SafeCast for uint256;

    function isCreated(Types.Market storage market) internal view returns (bool) {
        return market.underlying != address(0);
    }

    function isCreatedMem(Types.Market memory market) internal pure returns (bool) {
        return market.underlying != address(0);
    }

    function getIndexes(Types.Market storage market) internal view returns (Types.IndexesMem memory indexes) {
        indexes.poolSupplyIndex = uint256(market.indexes.poolSupplyIndex);
        indexes.poolBorrowIndex = uint256(market.indexes.poolBorrowIndex);
        indexes.p2pSupplyIndex = uint256(market.indexes.p2pSupplyIndex);
        indexes.p2pBorrowIndex = uint256(market.indexes.p2pBorrowIndex);
    }

    function setIndexes(Types.Market storage market, Types.IndexesMem memory indexes) internal {
        market.indexes.poolSupplyIndex = indexes.poolSupplyIndex.toUint128();
        market.indexes.poolBorrowIndex = indexes.poolBorrowIndex.toUint128();
        market.indexes.p2pSupplyIndex = indexes.p2pSupplyIndex.toUint128();
        market.indexes.p2pBorrowIndex = indexes.p2pBorrowIndex.toUint128();
        market.lastUpdateTimestamp = block.timestamp.toUint32();
    }
}
