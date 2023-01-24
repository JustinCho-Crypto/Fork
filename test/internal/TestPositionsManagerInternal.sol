// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

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

contract TestPositionsManagerInternal is InternalTest, PositionsManagerInternal {
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

    IPriceOracleGetter internal oracle;
    address internal poolConfigurator;
    address internal poolOwner;

    function setUp() public virtual override {
        poolConfigurator = addressesProvider.getPoolConfigurator();
        poolOwner = Ownable(address(addressesProvider)).owner();

        _defaultMaxLoops = Types.MaxLoops(10, 10);

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

        oracle = IPriceOracleGetter(_ADDRESSES_PROVIDER.getPriceOracle());
    }

    function testValidatePermission(address owner, address manager) public {
        _validatePermission(owner, owner);

        if (owner != manager) {
            vm.expectRevert(abi.encodeWithSelector(Errors.PermissionDenied.selector));
            _validatePermission(owner, manager);
        }

        _approveManager(owner, manager, true);
        _validatePermission(owner, manager);

        _approveManager(owner, manager, false);
        if (owner != manager) {
            vm.expectRevert(abi.encodeWithSelector(Errors.PermissionDenied.selector));
            _validatePermission(owner, manager);
        }
    }

    function testValidateInputRevertsIfAddressIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressIsZero.selector));
        _validateInput(dai, 1, address(0));
    }

    function testValidateInputRevertsIfAmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AmountIsZero.selector));
        _validateInput(dai, 0, address(1));
    }

    function testValidateInputRevertsIfMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotCreated.selector));
        _validateInput(address(0), 1, address(1));
    }

    function testValidateInput() public {
        _market[address(1)].aToken = address(2);
        _validateInput(dai, 1, address(1));
    }

    function testValidateManagerInput() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.AddressIsZero.selector));
        _validateManagerInput(dai, 1, address(0), address(1));
        _validateManagerInput(dai, 1, address(1), address(2));
    }

    function testValidateSupplyShouldRevertIfSupplyPaused() public {
        _market[dai].pauseStatuses.isSupplyPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.SupplyIsPaused.selector));
        _validateSupply(dai, 1, address(1));
    }

    function testValidateSupply() public view {
        _validateSupply(dai, 1, address(1));
    }

    function testValidateSupplyCollateralShouldRevertIfSupplyCollateralPaused() public {
        _market[dai].pauseStatuses.isSupplyCollateralPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.SupplyCollateralIsPaused.selector));
        _validateSupplyCollateral(dai, 1, address(1));
    }

    function testValidateSupplyCollateral() public view {
        _validateSupplyCollateral(dai, 1, address(1));
    }

    // Can't expect a revert if the internal function does not call a function that immediately reverts, so an external helper is needed.
    function validateBorrow(address underlying, uint256 amount, address borrower, address receiver) external view {
        _validateBorrow(underlying, amount, borrower, receiver);
    }

    function testValidateBorrowShouldRevertIfBorrowPaused() public {
        _market[dai].pauseStatuses.isBorrowPaused = true;
        vm.expectRevert(abi.encodeWithSelector(Errors.BorrowIsPaused.selector));
        this.validateBorrow(dai, 1, address(this), address(this));
    }

    function testValidateBorrowShouldRevertIfBorrowingNotEnabled() public {
        DataTypes.ReserveConfigurationMap memory reserveConfig = _POOL.getConfiguration(dai);
        reserveConfig.setBorrowingEnabled(false);
        assertFalse(reserveConfig.getBorrowingEnabled());

        vm.prank(poolConfigurator);
        _POOL.setConfiguration(dai, reserveConfig);

        vm.expectRevert(abi.encodeWithSelector(Errors.BorrowingNotEnabled.selector));
        this.validateBorrow(dai, 1, address(this), address(this));
    }

    function testValidateBorrow(uint256 onPool, uint256 inP2P) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        inP2P = bound(inP2P, MIN_AMOUNT, MAX_AMOUNT);
        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDiv(indexes.supply.poolIndex);

        this.validateBorrow(dai, onPool / 4, address(this), address(this));

        DataTypes.ReserveConfigurationMap memory config = _POOL.getConfiguration(dai);
        config.setEModeCategory(1);
        vm.prank(poolConfigurator);
        _POOL.setConfiguration(dai, config);

        this.validateBorrow(dai, onPool / 4, address(this), address(this));
    }

    function authorizeBorrow(address underlying, uint256 onPool, address borrower) public view {
        _authorizeBorrow(underlying, onPool, borrower);
    }

    function testAuthorizeBorrowShouldFailIfDebtTooHigh(uint256 onPool) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDiv(indexes.supply.poolIndex);

        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedBorrow.selector));
        this.authorizeBorrow(dai, onPool, address(this));
    }

    function testValidateRepayShouldRevertIfRepayPaused() public {
        _market[dai].pauseStatuses.isRepayPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.RepayIsPaused.selector));
        _validateRepay(dai, 1, address(1));
    }

    function testValidateRepay() public view {
        _validateRepay(dai, 1, address(1));
    }

    // Can't expect a revert if the internal function does not call a function that immediately reverts, so an external helper is needed.
    function validateWithdraw(address underlying, uint256 amount, address user, address to) external view {
        _validateWithdraw(underlying, amount, user, to);
    }

    function testValidateWithdrawShouldRevertIfWithdrawPaused() public {
        _market[dai].pauseStatuses.isWithdrawPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.WithdrawIsPaused.selector));
        this.validateWithdraw(dai, 1, address(this), address(this));
    }

    function testValidateWithdraw() public view {
        this.validateWithdraw(dai, 1, address(this), address(this));
    }

    function validateWithdrawCollateral(address underlying, uint256 amount, address supplier, address receiver)
        external
        view
    {
        _validateWithdrawCollateral(underlying, amount, supplier, receiver);
    }

    function validateWithdrawCollateral(address underlying, uint256 amount, address supplier) external view {
        this.validateWithdrawCollateral(underlying, amount, supplier);
    }

    function testValidateWithdrawCollateralShouldRevertIfWithdrawCollateralPaused() public {
        _market[dai].pauseStatuses.isWithdrawCollateralPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.WithdrawCollateralIsPaused.selector));
        this.validateWithdrawCollateral(dai, 1, address(this), address(this));
    }

    function testValidateWithdrawCollateral(uint256 onPool) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);
        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDivUp(indexes.supply.poolIndex);
        this.validateWithdrawCollateral(dai, onPool, address(this), address(this));
    }

    function authorizeWithdrawCollateral(address underlying, uint256 amount, address supplier) external view {
        _authorizeWithdrawCollateral(underlying, amount, supplier);
    }

    function testAuthorizeWithdrawCollateralShouldRevertIfHealthFactorTooLow(uint256 onPool) public {
        onPool = bound(onPool, MIN_AMOUNT, MAX_AMOUNT);
        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = onPool.rayDiv(indexes.supply.poolIndex);
        _userBorrows[address(this)].add(dai);
        _updateBorrowerInDS(dai, address(this), onPool.rayDiv(indexes.borrow.poolIndex) / 2, 0, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedWithdraw.selector));
        this.authorizeWithdrawCollateral(dai, onPool.rayDiv(indexes.supply.poolIndex) / 2, address(this));
    }

    // Can't expect a revert if the internal function does not call a function that immediately reverts, so an external helper is needed.
    function authorizeLiquidate(address collateral, address borrow, address liquidator)
        external
        view
        returns (uint256)
    {
        return _authorizeLiquidate(collateral, borrow, liquidator);
    }

    function testAuthorizeLiquidateIfBorrowMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotCreated.selector));
        this.authorizeLiquidate(address(420), dai, address(this));
    }

    function testAuthorizeLiquidateIfCollateralMarketNotCreated() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MarketNotCreated.selector));
        this.authorizeLiquidate(dai, address(420), address(this));
    }

    function testAuthorizeLiquidateIfLiquidateCollateralPaused() public {
        _market[dai].pauseStatuses.isLiquidateCollateralPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.LiquidateCollateralIsPaused.selector));
        this.authorizeLiquidate(dai, dai, address(this));
    }

    function testAuthorizeLiquidateIfLiquidateBorrowPaused() public {
        _market[dai].pauseStatuses.isLiquidateBorrowPaused = true;

        vm.expectRevert(abi.encodeWithSelector(Errors.LiquidateBorrowIsPaused.selector));
        this.authorizeLiquidate(dai, dai, address(this));
    }

    function testAuthorizeLiquidateShouldReturnMaxCloseFactorIfDeprecatedBorrow() public {
        _userCollaterals[address(this)].add(dai);
        _userBorrows[address(this)].add(dai);
        _market[dai].pauseStatuses.isDeprecated = true;
        uint256 closeFactor = this.authorizeLiquidate(dai, dai, address(this));
        assertEq(closeFactor, Constants.MAX_CLOSE_FACTOR);
    }

    function testAuthorizeLiquidateShouldRevertIfSentinelDisallows() public {
        uint256 amount = 1e18;
        (, uint256 lt,,,,) = _POOL.getConfiguration(dai).getParams();
        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = amount.rayDiv(indexes.supply.poolIndex);
        _userBorrows[address(this)].add(dai);
        _updateBorrowerInDS(
            dai, address(this), amount.rayDiv(indexes.borrow.poolIndex).percentMulUp(lt * 101 / 100), 0, true
        );

        MockPriceOracleSentinel priceOracleSentinel = new MockPriceOracleSentinel(address(_ADDRESSES_PROVIDER));
        priceOracleSentinel.setLiquidationAllowed(false);
        vm.prank(poolOwner);
        _ADDRESSES_PROVIDER.setPriceOracleSentinel(address(priceOracleSentinel));

        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedLiquidate.selector));
        this.authorizeLiquidate(dai, dai, address(this));
    }

    function testAuthorizeLiquidateShouldRevertIfBorrowerHealthy() public {
        uint256 amount = 1e18;
        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = amount.rayDiv(indexes.supply.poolIndex);
        _userBorrows[address(this)].add(dai);
        _updateBorrowerInDS(dai, address(this), amount.rayDiv(indexes.borrow.poolIndex).percentMulDown(50_00), 0, true);

        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedLiquidate.selector));
        this.authorizeLiquidate(dai, dai, address(this));
    }

    function testAuthorizeLiquidateShouldReturnMaxCloseFactorIfBelowMinThreshold() public {
        uint256 amount = 1e18;
        (, uint256 lt,,,,) = _POOL.getConfiguration(dai).getParams();
        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = amount.rayDiv(indexes.supply.poolIndex);
        _userBorrows[address(this)].add(dai);
        _updateBorrowerInDS(
            dai, address(this), amount.rayDiv(indexes.borrow.poolIndex).percentMulUp(lt * 11 / 10), 0, true
        );

        uint256 closeFactor = this.authorizeLiquidate(dai, dai, address(this));
        assertEq(closeFactor, Constants.MAX_CLOSE_FACTOR);
    }

    function testAuthorizeLiquidateShouldReturnDefaultCloseFactorIfAboveMinThreshold() public {
        uint256 amount = 1e18;
        (, uint256 lt,,,,) = _POOL.getConfiguration(dai).getParams();
        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);

        _userCollaterals[address(this)].add(dai);
        _marketBalances[dai].collateral[address(this)] = amount.rayDiv(indexes.supply.poolIndex);
        _userBorrows[address(this)].add(dai);
        _updateBorrowerInDS(
            dai, address(this), amount.rayDiv(indexes.borrow.poolIndex).percentMulUp(lt * 101 / 100), 0, true
        );

        uint256 closeFactor = this.authorizeLiquidate(dai, dai, address(this));
        assertEq(closeFactor, Constants.DEFAULT_CLOSE_FACTOR);
    }

    function testAddToPool(uint256 amount, uint256 onPool, uint256 poolIndex) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        onPool = bound(onPool, 0, MAX_AMOUNT);
        poolIndex = bound(poolIndex, WadRayMath.RAY, WadRayMath.RAY * 10);

        (uint256 newAmount, uint256 newOnPool) = _addToPool(amount, onPool, poolIndex);
        assertEq(newAmount, amount);
        assertEq(newOnPool, onPool + amount.rayDivDown(poolIndex));
    }

    function testSubFromPool(uint256 amount, uint256 onPool, uint256 poolIndex) public {
        amount = bound(amount, 0, MAX_AMOUNT);
        onPool = bound(onPool, 0, MAX_AMOUNT);
        poolIndex = bound(poolIndex, WadRayMath.RAY, WadRayMath.RAY * 10);

        (uint256 newAmount, uint256 newAmountLeft, uint256 newOnPool) = _subFromPool(amount, onPool, poolIndex);
        assertEq(newAmount, Math.min(onPool.rayMul(poolIndex), amount));
        assertEq(newAmountLeft, amount - newAmount);
        assertEq(newOnPool, onPool - Math.min(onPool, newAmount.rayDivUp(poolIndex)));
    }

    function testPromoteSuppliersRoutine(uint256 amount, uint256 maxLoops) public {
        amount = bound(amount, 0, 1 ether * 20);
        maxLoops = bound(maxLoops, 0, 20);

        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);

        for (uint256 i; i < 10; i++) {
            _updateSupplierInDS(dai, vm.addr(i + 1), uint256(1 ether).rayDiv(indexes.supply.poolIndex), 0, true);
        }

        (uint256 toProcess, uint256 amountLeft, uint256 maxLoopsLeft) =
            _promoteRoutine(dai, amount, maxLoops, _promoteSuppliers);

        uint256 maxExpectedLoops = Math.min(maxLoops, 10);
        uint256 expectedLoops = amount > 1 ether * maxExpectedLoops ? maxExpectedLoops : amount.divUp(1 ether);

        uint256 expectedToProcess = Math.min(amount, expectedLoops * 1 ether);
        uint256 expectedAmountLeft = amount - expectedToProcess;
        uint256 expectedMaxLoopsLeft = maxLoops - expectedLoops;
        assertEq(toProcess, expectedToProcess, "toProcess");
        assertEq(amountLeft, expectedAmountLeft, "amountLeft");
        assertEq(maxLoopsLeft, expectedMaxLoopsLeft, "maxLoopsLeft");
    }

    function testPromoteBorrowersRoutine(uint256 amount, uint256 maxLoops) public {
        amount = bound(amount, 0, 1 ether * 20);
        maxLoops = bound(maxLoops, 0, 20);

        (, Types.Indexes256 memory indexes) = _computeIndexes(dai);

        for (uint256 i; i < 10; i++) {
            _updateBorrowerInDS(dai, vm.addr(i + 1), uint256(1 ether).rayDiv(indexes.borrow.poolIndex), 0, true);
        }

        (uint256 toProcess, uint256 amountLeft, uint256 maxLoopsLeft) =
            _promoteRoutine(dai, amount, maxLoops, _promoteBorrowers);

        uint256 maxExpectedLoops = Math.min(maxLoops, 10);
        uint256 expectedLoops = amount > 1 ether * maxExpectedLoops ? maxExpectedLoops : amount.divUp(1 ether);

        uint256 expectedToProcess = Math.min(amount, maxExpectedLoops * 1 ether);
        uint256 expectedAmountLeft = amount - expectedToProcess;
        uint256 expectedMaxLoopsLeft = maxLoops - expectedLoops;
        assertEq(toProcess, expectedToProcess, "toProcess");
        assertEq(amountLeft, expectedAmountLeft, "amountLeft");
        assertEq(maxLoopsLeft, expectedMaxLoopsLeft, "maxLoopsLeft");
    }
}
