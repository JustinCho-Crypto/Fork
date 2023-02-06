// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {Errors} from "src/libraries/Errors.sol";
import {MorphoStorage} from "src/MorphoStorage.sol";
import {PositionsManagerInternal} from "src/PositionsManagerInternal.sol";

import {Types} from "src/libraries/Types.sol";
import {Constants} from "src/libraries/Constants.sol";

import {TestConfigLib, TestConfig} from "../helpers/TestConfigLib.sol";
import {PoolLib} from "src/libraries/PoolLib.sol";
import {MarketLib} from "src/libraries/MarketLib.sol";

import {MockPriceOracleSentinel} from "../mock/MockPriceOracleSentinel.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IPriceOracleGetter} from "@aave-v3-core/interfaces/IPriceOracleGetter.sol";
import {IPriceOracleSentinel} from "@aave-v3-core/interfaces/IPriceOracleSentinel.sol";
import {IPool, IPoolAddressesProvider} from "@aave-v3-core/interfaces/IPool.sol";

import {SafeTransferLib, ERC20} from "@solmate/utils/SafeTransferLib.sol";

import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import {WadRayMath} from "@morpho-utils/math/WadRayMath.sol";
import {PercentageMath} from "@morpho-utils/math/PercentageMath.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "test/helpers/InternalTest.sol";

contract TestInternalPositionsManagerInternal is InternalTest, PositionsManagerInternal {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using EnumerableSet for EnumerableSet.AddressSet;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using TestConfigLib for TestConfig;
    using PoolLib for IPool;
    using MarketLib for Types.Market;
    using SafeTransferLib for ERC20;
    using Math for uint256;

    uint256 constant MIN_AMOUNT = 1 ether;
    uint256 constant MAX_AMOUNT = type(uint96).max / 2;

    IPriceOracleGetter internal priceOracle;
    address internal poolOwner;

    function setUp() public virtual override {
        poolOwner = Ownable(address(addressesProvider)).owner();

        _defaultMaxIterations = Types.MaxIterations(10, 10);

        _createMarket(dai, 0, 3_333);
        _createMarket(wbtc, 0, 3_333);
        _createMarket(usdc, 0, 3_333);
        _createMarket(usdt, 0, 3_333);
        _createMarket(wNative, 0, 3_333);

        _setBalances(address(this), type(uint256).max);

        _POOL.supplyToPool(dai, 100 ether);
        _POOL.supplyToPool(wbtc, 1e8);
        _POOL.supplyToPool(usdc, 1e8);
        _POOL.supplyToPool(usdt, 1e8);
        _POOL.supplyToPool(wNative, 1 ether);

        priceOracle = IPriceOracleGetter(_ADDRESSES_PROVIDER.getPriceOracle());
    }

    function testAuthorizeBorrowShouldRevertIfExceedsBorrowCap() public {}

    function testAccountBorrowShouldDecreaseIdleSupplyIfIdleSupplyExists() public {}

    function testAccountRepayShouldIncreaseIdleSupplyIfSupplyCapReached() public {}

    function testAccountWithdrawShouldDecreaseIdleSupplyIfIdleSupplyExists() public {}
}
