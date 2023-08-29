//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/Mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine public engine;
    HelperConfig public config;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    address public LUSER = makeAddr("luser");
    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    uint256 public collateralToCover = 20 ether;
    event collateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
        vm.deal(USER, STARTING_ERC20_BALANCE);
        vm.deal(LUSER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL * 2);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier mintedDSC() {
        vm.startPrank(USER);
        engine.mintDsc(engine.getUsdValue(weth, AMOUNT_COLLATERAL / 2));
        vm.stopPrank();
        _;
    }
    modifier depositAndMintDSC() {
        vm.startPrank(USER); 
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL); 
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint); 
        vm.stopPrank();
        _; 
    }
    function testHealthFactorIsCorrect() public depositedCollateral mintedDSC{
     uint256 healthFactor = engine.getHealthFactor(USER);
     uint256 hardcodedHealthFactor= 1e18;
     assertEq(healthFactor, hardcodedHealthFactor);
    }
    
    function testLiquadateIsWorking() public depositAndMintDSC {
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18
        console.log(engine.getUsdValue(weth, 1));
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = engine.getHealthFactor(USER);
        (uint256 totalDscMinted, uint256 collateralValue) = engine.getAccountInformation(USER);
        console.log("DSC minted:", totalDscMinted, "value of collateral:", collateralValue);
        console.log(userHealthFactor);
        console.log(engine.getUsdValue(weth, 1));
        ERC20Mock(weth).mint(LUSER, collateralToCover);
        vm.startPrank(LUSER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL * 2);
        engine.depositCollateralAndMintDsc(weth, collateralToCover, AMOUNT_COLLATERAL * 2);
        dsc.approve(address(engine), AMOUNT_COLLATERAL * 2);
        engine.liquidate(weth, USER, AMOUNT_COLLATERAL * 2);
        vm.stopPrank();
        uint256 liquidationGain = 1222222222222222222; 
        assertEq(liquidationGain, ERC20Mock(weth).balanceOf(LUSER)); 
        assertEq(engine.getCollateralBalanceOfUser(USER, weth), AMOUNT_COLLATERAL - liquidationGain);
    }

    function testCantLiquidateIfHealhFactorIsOk() public depositedCollateral mintedDSC {
        console.log("health factor of the user:", engine.getHealthFactor(USER));
        vm.prank(LUSER);
        vm.expectRevert(DSCEngine.DSC_HealthFactorOk.selector);
        engine.liquidate(address(weth), USER, 5);
    }

    function testBurnIsWorking() public depositedCollateral {
        vm.startPrank(USER);
        engine.mintDsc(engine.getUsdValue(weth, AMOUNT_COLLATERAL / 4));

        dsc.increaseAllowance(address(engine), engine.getUsdValue(weth, AMOUNT_COLLATERAL / 4));

        engine.burnDsc(engine.getUsdValue(weth, AMOUNT_COLLATERAL / 4));
        vm.stopPrank();
        (uint256 totalMinted,) = engine.getAccountInformation(USER);
        assert(totalMinted == 0);
    }

    function testBurnIsRevertIfNotMoreThanZero() public depositedCollateral {
        engine.mintDsc(engine.getUsdValue(weth, AMOUNT_COLLATERAL / 4));
        vm.stopPrank();
        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        engine.burnDsc(0);
    }
    function testCollateralDepositedEmit() public {
         vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL * 2);
        vm.expectEmit(true, true, true, false); 
        emit collateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

    }
    function testRedeemCollateralIsWorking() public depositedCollateral {
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();

        (, uint256 collateral) = engine.getAccountInformation(USER);
        assert(collateral == 0);
    }

    function testDepositAndMint() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, engine.getUsdValue(weth, AMOUNT_COLLATERAL) / 4);
    }

    function testMintISRevertIfHealthFactorIsBroken() public depositedCollateral {
        engine.mintDsc(engine.getUsdValue(weth, AMOUNT_COLLATERAL) / 4);
        vm.stopPrank();
        (uint256 totaldscMinted,) = engine.getAccountInformation(USER);
        assert(totaldscMinted == engine.getUsdValue(weth, AMOUNT_COLLATERAL) / 4);
    }

    function testCanDepositCollateralAndGetCountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueinUsd) = engine.getAccountInformation(USER);
        uint256 expectedtotalDscMinted = 0;
        uint256 expectedDepositValueinUsd = engine.getTokenAmountFromsUsd(weth, collateralValueinUsd);
        assertEq(totalDscMinted, expectedtotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositValueinUsd);
    }

    function testRevertWithUnapprouvedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine_NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromsUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthNotMatchWithPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses,priceFeedAddresses,address(engine));
    }

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);

        assert(expectUsd == actualUsd);
    }

    function testRevertIfCollateralEgalZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine_NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
