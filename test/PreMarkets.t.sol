// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {SystemConfig} from "../src/core/SystemConfig.sol";
import {CapitalPool} from "../src/core/CapitalPool.sol";
import {TokenManager} from "../src/core/TokenManager.sol";
import {PreMarktes} from "../src/core/PreMarkets.sol";
import {DeliveryPlace} from "../src/core/DeliveryPlace.sol";
import {TadleFactory} from "../src/factory/TadleFactory.sol";

import {OfferStatus, StockStatus, AbortOfferStatus, OfferType, StockType, OfferSettleType} from "../src/storage/OfferStatus.sol";
import {IPerMarkets, OfferInfo, StockInfo, MakerInfo, CreateOfferParams} from "../src/interfaces/IPerMarkets.sol";
import {TokenBalanceType, ITokenManager} from "../src/interfaces/ITokenManager.sol";

import {GenerateAddress} from "../src/libraries/GenerateAddress.sol";

import {Rescuable} from "../src/utils/Rescuable.sol";
import {MockERC20Token} from "./mocks/MockERC20Token.sol";
import {WETH9} from "./mocks/WETH9.sol";
import {UpgradeableProxy} from "../src/proxy/UpgradeableProxy.sol";

contract PreMarketsTest is Test {
    SystemConfig systemConfig;
    CapitalPool capitalPool;
    TokenManager tokenManager;
    PreMarktes preMarktes;
    DeliveryPlace deliveryPlace;

    address marketPlace;
    WETH9 weth9;
    MockERC20Token mockUSDCToken;
    MockERC20Token mockPointToken;

    address user = vm.addr(1);
    address user1 = vm.addr(2);
    address user2 = vm.addr(3);
    address user3 = vm.addr(4);

    address manager = vm.addr(5);
    address guardian = vm.addr(6);

    uint256 basePlatformFeeRate = 5_000;
    uint256 baseReferralRate = 300_000;

    bytes4 private constant INITIALIZE_OWNERSHIP_SELECTOR =
        bytes4(keccak256(bytes("initializeOwnership(address)")));

    function setUp() public {
        // deploy mocks
        weth9 = new WETH9();

        TadleFactory tadleFactory = new TadleFactory(guardian);

        mockUSDCToken = new MockERC20Token();
        mockPointToken = new MockERC20Token();

        SystemConfig systemConfigLogic = new SystemConfig();
        CapitalPool capitalPoolLogic = new CapitalPool();
        TokenManager tokenManagerLogic = new TokenManager();
        PreMarktes preMarktesLogic = new PreMarktes();
        DeliveryPlace deliveryPlaceLogic = new DeliveryPlace();

        vm.startPrank(guardian);
        address systemConfigProxy = tadleFactory.deployUpgradeableProxy(
            1,
            address(systemConfigLogic),
            manager
        );

        address preMarktesProxy = tadleFactory.deployUpgradeableProxy(
            2,
            address(preMarktesLogic),
            manager
        );
        address deliveryPlaceProxy = tadleFactory.deployUpgradeableProxy(
            3,
            address(deliveryPlaceLogic),
            manager
        );
        address capitalPoolProxy = tadleFactory.deployUpgradeableProxy(
            4,
            address(capitalPoolLogic),
            manager
        );
        address tokenManagerProxy = tadleFactory.deployUpgradeableProxy(
            5,
            address(tokenManagerLogic),
            manager
        );

        vm.stopPrank();
        // attach logic
        systemConfig = SystemConfig(systemConfigProxy);
        capitalPool = CapitalPool(capitalPoolProxy);
        tokenManager = TokenManager(tokenManagerProxy);
        preMarktes = PreMarktes(preMarktesProxy);
        deliveryPlace = DeliveryPlace(deliveryPlaceProxy);

        vm.startPrank(manager);
        // initialize
        systemConfig.initialize(basePlatformFeeRate, baseReferralRate);

        tokenManager.initialize(address(weth9));
        address[] memory tokenAddressList = new address[](2);

        tokenAddressList[0] = address(mockUSDCToken);
        tokenAddressList[1] = address(weth9);

        tokenManager.updateTokenWhiteListed(tokenAddressList, true);

        // create market place
        systemConfig.createMarketPlace("Backpack", false);
        vm.stopPrank();

        deal(address(mockUSDCToken), user, 100000000 * 10 ** 18);
        deal(address(mockPointToken), user, 100000000 * 10 ** 18);
        deal(user, 100000000 * 10 ** 18);

        deal(address(mockUSDCToken), user1, 100000000 * 10 ** 18);
        deal(address(mockUSDCToken), user2, 100000000 * 10 ** 18);
        deal(address(mockUSDCToken), user3, 100000000 * 10 ** 18);

        deal(address(mockPointToken), user2, 100000000 * 10 ** 18);

        marketPlace = GenerateAddress.generateMarketPlaceAddress("Backpack");

        vm.warp(1719826275);

        vm.prank(user);
        mockUSDCToken.approve(address(tokenManager), type(uint256).max);

        vm.startPrank(user2);
        mockUSDCToken.approve(address(tokenManager), type(uint256).max);
        mockPointToken.approve(address(tokenManager), type(uint256).max);
        vm.stopPrank();
    }

    function test_ask_offer_turbo_usdc() public {
        vm.startPrank(user);
        preMarktes.createOffer(
            CreateOfferParams(
                marketPlace,
                address(mockUSDCToken),
                1000,
                0.01 * 1e18,
                12000,
                300,
                OfferType.Ask,
                OfferSettleType.Turbo
            )
        );

        address offerAddr = GenerateAddress.generateOfferAddress(1);
        preMarktes.createTaker(offerAddr, 500);

        address stock1Addr = GenerateAddress.generateStockAddress(2);
        preMarktes.listOffer(stock1Addr, 0.006 * 1e18, 12000);

        address offer1Addr = GenerateAddress.generateOfferAddress(2);
        preMarktes.closeOffer(stock1Addr, offer1Addr);
        preMarktes.relistOffer(stock1Addr, offer1Addr);

        vm.stopPrank();

        vm.prank(manager);
        systemConfig.updateMarket(
            "Backpack",
            address(mockPointToken),
            0.01 * 1e18,
            block.timestamp - 1,
            3600
        );

        vm.startPrank(user);
        mockPointToken.approve(address(tokenManager), 10000 * 10 ** 18);
        deliveryPlace.settleAskMaker(offerAddr, 500);
        deliveryPlace.closeBidTaker(stock1Addr);
        vm.stopPrank();
    }

    function test_ask_offer_protected_usdc() public {
        vm.startPrank(user);

        preMarktes.createOffer(
            CreateOfferParams(
                marketPlace,
                address(mockUSDCToken),
                1000,
                0.01 * 1e18,
                12000,
                300,
                OfferType.Ask,
                OfferSettleType.Protected
            )
        );

        address offerAddr = GenerateAddress.generateOfferAddress(1);
        preMarktes.createTaker(offerAddr, 500);

        address stock1Addr = GenerateAddress.generateStockAddress(2);
        preMarktes.listOffer(stock1Addr, 0.006 * 1e18, 12000);

        address offer1Addr = GenerateAddress.generateOfferAddress(2);
        preMarktes.closeOffer(stock1Addr, offer1Addr);
        preMarktes.relistOffer(stock1Addr, offer1Addr);

        vm.stopPrank();

        vm.prank(manager);
        systemConfig.updateMarket(
            "Backpack",
            address(mockPointToken),
            0.01 * 1e18,
            block.timestamp - 1,
            3600
        );

        vm.startPrank(user);
        mockPointToken.approve(address(tokenManager), 10000 * 10 ** 18);
        deliveryPlace.settleAskMaker(offerAddr, 500);
        deliveryPlace.closeBidTaker(stock1Addr);
        vm.stopPrank();
    }

    function test_create_bid_offer_turbo_usdc() public {
        vm.startPrank(user);

        preMarktes.createOffer(
            CreateOfferParams(
                marketPlace,
                address(mockUSDCToken),
                1000,
                0.01 * 1e18,
                12000,
                300,
                OfferType.Bid,
                OfferSettleType.Turbo
            )
        );

        address offerAddr = GenerateAddress.generateOfferAddress(1);
        preMarktes.createTaker(offerAddr, 500);

        address stock1Addr = GenerateAddress.generateStockAddress(2);
        vm.stopPrank();

        vm.prank(manager);
        systemConfig.updateMarket(
            "Backpack",
            address(mockPointToken),
            0.01 * 1e18,
            block.timestamp - 1,
            3600
        );

        vm.startPrank(user);
        mockPointToken.approve(address(tokenManager), 10000 * 10 ** 18);

        deliveryPlace.settleAskTaker(stock1Addr, 500);
        vm.stopPrank();
    }

    function test_ask_offer_turbo_eth() public {
        vm.startPrank(user);

        preMarktes.createOffer{value: 0.012 * 1e18}(
            CreateOfferParams(
                marketPlace,
                address(weth9),
                1000,
                0.01 * 1e18,
                12000,
                300,
                OfferType.Ask,
                OfferSettleType.Turbo
            )
        );

        address offerAddr = GenerateAddress.generateOfferAddress(1);
        preMarktes.createTaker{value: 0.005175 * 1e18}(offerAddr, 500);

        address stock1Addr = GenerateAddress.generateStockAddress(2);
        preMarktes.listOffer(stock1Addr, 0.006 * 1e18, 12000);

        address offer1Addr = GenerateAddress.generateOfferAddress(2);
        preMarktes.closeOffer(stock1Addr, offer1Addr);
        preMarktes.relistOffer(stock1Addr, offer1Addr);

        vm.stopPrank();

        vm.prank(manager);
        systemConfig.updateMarket(
            "Backpack",
            address(mockPointToken),
            0.01 * 1e18,
            block.timestamp - 1,
            3600
        );

        vm.startPrank(user);
        mockPointToken.approve(address(tokenManager), 10000 * 10 ** 18);
        deliveryPlace.settleAskMaker(offerAddr, 500);
        deliveryPlace.closeBidTaker(stock1Addr);
        vm.stopPrank();
    }

    function test_ask_offer_protected_eth() public {
        vm.startPrank(user);

        preMarktes.createOffer{value: 0.012 * 1e18}(
            CreateOfferParams(
                marketPlace,
                address(weth9),
                1000,
                0.01 * 1e18,
                12000,
                300,
                OfferType.Ask,
                OfferSettleType.Protected
            )
        );

        address offerAddr = GenerateAddress.generateOfferAddress(1);
        preMarktes.createTaker{value: 0.005175 * 1e18}(offerAddr, 500);

        address stock1Addr = GenerateAddress.generateStockAddress(2);
        preMarktes.listOffer{value: 0.0072 * 1e18}(
            stock1Addr,
            0.006 * 1e18,
            12000
        );

        address offer1Addr = GenerateAddress.generateOfferAddress(2);
        preMarktes.closeOffer(stock1Addr, offer1Addr);
        preMarktes.relistOffer{value: 0.0072 * 1e18}(stock1Addr, offer1Addr);

        vm.stopPrank();

        vm.prank(manager);
        systemConfig.updateMarket(
            "Backpack",
            address(mockPointToken),
            0.01 * 1e18,
            block.timestamp - 1,
            3600
        );

        vm.startPrank(user);
        mockPointToken.approve(address(tokenManager), 10000 * 10 ** 18);
        deliveryPlace.settleAskMaker(offerAddr, 500);
        deliveryPlace.closeBidTaker(stock1Addr);
        vm.stopPrank();
    }

    function test_create_bid_offer_turbo_eth() public {
        vm.startPrank(user);

        preMarktes.createOffer{value: 0.01 * 1e18}(
            CreateOfferParams(
                marketPlace,
                address(weth9),
                1000,
                0.01 * 1e18,
                12000,
                300,
                OfferType.Bid,
                OfferSettleType.Turbo
            )
        );

        address offerAddr = GenerateAddress.generateOfferAddress(1);
        preMarktes.createTaker{value: 0.006175 * 1e18}(offerAddr, 500);

        address stock1Addr = GenerateAddress.generateStockAddress(2);
        vm.stopPrank();

        vm.prank(manager);
        systemConfig.updateMarket(
            "Backpack",
            address(mockPointToken),
            0.01 * 1e18,
            block.timestamp - 1,
            3600
        );

        vm.startPrank(user);
        mockPointToken.approve(address(tokenManager), 10000 * 10 ** 18);

        deliveryPlace.settleAskTaker(stock1Addr, 500);
        vm.stopPrank();
    }

    function test_ask_turbo_chain() public {
        vm.startPrank(user);

        uint256 userUSDTBalance0 = mockUSDCToken.balanceOf(user);
        preMarktes.createOffer(
            CreateOfferParams(
                marketPlace,
                address(mockUSDCToken),
                1000,
                0.01 * 1e18,
                12000,
                300,
                OfferType.Ask,
                OfferSettleType.Turbo
            )
        );

        uint256 userUSDTBalance1 = mockUSDCToken.balanceOf(user);
        assertEq(userUSDTBalance1, userUSDTBalance0 - 0.012 * 1e18);

        address offerAddr = GenerateAddress.generateOfferAddress(1);
        vm.stopPrank();

        vm.startPrank(user1);

        uint256 user1USDTBalance0 = mockUSDCToken.balanceOf(user1);
        uint256 userTaxIncomeBalance0 = tokenManager.userTokenBalanceMap(
            address(user),
            address(mockUSDCToken),
            TokenBalanceType.TaxIncome
        );
        uint256 userSalesRevenue0 = tokenManager.userTokenBalanceMap(
            address(user),
            address(mockUSDCToken),
            TokenBalanceType.SalesRevenue
        );
        mockUSDCToken.approve(address(tokenManager), type(uint256).max);
        preMarktes.createTaker(offerAddr, 300);
        vm.stopPrank();

        uint256 user1USDTBalance1 = mockUSDCToken.balanceOf(user1);
        assertEq(
            user1USDTBalance1,
            user1USDTBalance0 - ((0.01 * 300) / 1000) * 1.035 * 1e18
        );
        uint256 userTaxIncomeBalance1 = tokenManager.userTokenBalanceMap(
            address(user),
            address(mockUSDCToken),
            TokenBalanceType.TaxIncome
        );
        assertEq(
            userTaxIncomeBalance1,
            userTaxIncomeBalance0 + ((0.01 * 300) / 1000) * 0.03 * 1e18
        );

        uint256 userSalesRevenue1 = tokenManager.userTokenBalanceMap(
            address(user),
            address(mockUSDCToken),
            TokenBalanceType.SalesRevenue
        );
        assertEq(
            userSalesRevenue1,
            userSalesRevenue0 + ((0.01 * 300) / 1000) * 1e18
        );

        vm.startPrank(user2);
        mockUSDCToken.approve(address(tokenManager), type(uint256).max);
        preMarktes.createTaker(offerAddr, 500);

        address stock2Addr = GenerateAddress.generateStockAddress(3);
        preMarktes.listOffer(stock2Addr, 0.006 * 1e18, 12000);
        vm.stopPrank();

        address offer2Addr = GenerateAddress.generateOfferAddress(3);
        vm.startPrank(user3);
        mockUSDCToken.approve(address(tokenManager), type(uint256).max);
        preMarktes.createTaker(offer2Addr, 200);
        vm.stopPrank();

        vm.startPrank(user);
        address originStock = GenerateAddress.generateStockAddress(1);
        address originOffer = GenerateAddress.generateOfferAddress(1);
        preMarktes.closeOffer(originStock, originOffer);
        preMarktes.relistOffer(originStock, originOffer);

        vm.stopPrank();

        vm.prank(manager);
        systemConfig.updateMarket(
            "Backpack",
            address(mockPointToken),
            0.01 * 1e18,
            block.timestamp - 1,
            3600
        );

        vm.startPrank(user);
        mockPointToken.approve(address(tokenManager), 10000 * 10 ** 18);
        deliveryPlace.settleAskMaker(offerAddr, 800);
        vm.stopPrank();

        vm.prank(user1);
        address stock1Addr = GenerateAddress.generateStockAddress(2);
        deliveryPlace.closeBidTaker(stock1Addr);

        vm.prank(user2);
        deliveryPlace.closeBidTaker(stock2Addr);

        vm.prank(user3);
        address stock3Addr = GenerateAddress.generateStockAddress(4);
        deliveryPlace.closeBidTaker(stock3Addr);
    }

    function test_ask_protected_chain() public {
        vm.startPrank(user);

        uint256 userUSDTBalance0 = mockUSDCToken.balanceOf(user);
        preMarktes.createOffer(
            CreateOfferParams(
                marketPlace,
                address(mockUSDCToken),
                1000,
                0.01 * 1e18,
                12000,
                300,
                OfferType.Ask,
                OfferSettleType.Protected
            )
        );

        uint256 userUSDTBalance1 = mockUSDCToken.balanceOf(user);
        assertEq(userUSDTBalance1, userUSDTBalance0 - 0.012 * 1e18);

        address offerAddr = GenerateAddress.generateOfferAddress(1);
        vm.stopPrank();

        vm.startPrank(user1);

        uint256 user1USDTBalance0 = mockUSDCToken.balanceOf(user1);
        uint256 userTaxIncomeBalance0 = tokenManager.userTokenBalanceMap(
            address(user),
            address(mockUSDCToken),
            TokenBalanceType.TaxIncome
        );
        uint256 userSalesRevenue0 = tokenManager.userTokenBalanceMap(
            address(user),
            address(mockUSDCToken),
            TokenBalanceType.SalesRevenue
        );
        mockUSDCToken.approve(address(tokenManager), type(uint256).max);
        preMarktes.createTaker(offerAddr, 300);
        vm.stopPrank();

        uint256 user1USDTBalance1 = mockUSDCToken.balanceOf(user1);
        assertEq(
            user1USDTBalance1,
            user1USDTBalance0 - ((0.01 * 300) / 1000) * 1.035 * 1e18
        );
        uint256 userTaxIncomeBalance1 = tokenManager.userTokenBalanceMap(
            address(user),
            address(mockUSDCToken),
            TokenBalanceType.TaxIncome
        );
        assertEq(
            userTaxIncomeBalance1,
            userTaxIncomeBalance0 + ((0.01 * 300) / 1000) * 0.03 * 1e18
        );

        uint256 userSalesRevenue1 = tokenManager.userTokenBalanceMap(
            address(user),
            address(mockUSDCToken),
            TokenBalanceType.SalesRevenue
        );
        assertEq(
            userSalesRevenue1,
            userSalesRevenue0 + ((0.01 * 300) / 1000) * 1e18
        );

        vm.startPrank(user2);
        mockUSDCToken.approve(address(tokenManager), type(uint256).max);
        preMarktes.createTaker(offerAddr, 500);

        address stock2Addr = GenerateAddress.generateStockAddress(3);
        preMarktes.listOffer(stock2Addr, 0.006 * 1e18, 12000);
        vm.stopPrank();

        address offer2Addr = GenerateAddress.generateOfferAddress(3);
        vm.startPrank(user3);
        mockUSDCToken.approve(address(tokenManager), type(uint256).max);
        preMarktes.createTaker(offer2Addr, 200);
        vm.stopPrank();

        vm.startPrank(user);
        address originStock = GenerateAddress.generateStockAddress(1);
        address originOffer = GenerateAddress.generateOfferAddress(1);
        preMarktes.closeOffer(originStock, originOffer);
        preMarktes.relistOffer(originStock, originOffer);

        vm.stopPrank();

        vm.prank(manager);
        systemConfig.updateMarket(
            "Backpack",
            address(mockPointToken),
            0.01 * 1e18,
            block.timestamp - 1,
            3600
        );

        vm.startPrank(user);
        mockPointToken.approve(address(tokenManager), 10000 * 10 ** 18);
        deliveryPlace.settleAskMaker(offerAddr, 800);
        vm.stopPrank();

        vm.prank(user1);
        address stock1Addr = GenerateAddress.generateStockAddress(2);
        deliveryPlace.closeBidTaker(stock1Addr);

        vm.prank(user2);
        deliveryPlace.closeBidTaker(stock2Addr);

        vm.prank(user2);
        deliveryPlace.settleAskMaker(offer2Addr, 200);

        vm.prank(user3);
        address stock3Addr = GenerateAddress.generateStockAddress(4);
        deliveryPlace.closeBidTaker(stock3Addr);
    }

    function test_abort_turbo_offer() public {
        vm.startPrank(user);

        preMarktes.createOffer(
            CreateOfferParams(
                marketPlace,
                address(mockUSDCToken),
                1000,
                0.01 * 1e18,
                12000,
                300,
                OfferType.Ask,
                OfferSettleType.Turbo
            )
        );
        vm.stopPrank();

        vm.startPrank(user1);
        mockUSDCToken.approve(address(tokenManager), type(uint256).max);
        address stockAddr = GenerateAddress.generateStockAddress(1);
        address offerAddr = GenerateAddress.generateOfferAddress(1);

        preMarktes.createTaker(offerAddr, 500);
        vm.stopPrank();

        vm.prank(user);
        preMarktes.abortAskOffer(stockAddr, offerAddr);
        vm.startPrank(user1);
        address stock1Addr = GenerateAddress.generateStockAddress(2);
        preMarktes.abortBidTaker(stock1Addr, offerAddr);
        vm.stopPrank();
    }

    function test_referral_code() public {
        vm.prank(user);
        systemConfig.createReferralCode("Egtk1OG2", 300000, 0);

        vm.prank(user1);
        systemConfig.updateReferrerInfo("Egtk1OG2");
    }
}
