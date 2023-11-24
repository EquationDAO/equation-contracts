import "dotenv/config";
import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";
import {getPoolBytecodeHash, initializePoolByteCode} from "../test/shared/address";
import {MultiMinter} from "../typechain-types";
import {concatPoolCreationCode} from "../test/shared/creationCode";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }

    const deployments = new Map<string, string>();
    // deploy libraries
    const {poolUtil, fundingRateUtil, priceUtil, positionUtil, liquidityPositionUtil} = await deployLibraries();
    const txReceipt = await poolUtil.provider.getTransactionReceipt(poolUtil.deployTransaction.hash);
    console.log(`First contract deployed at block ${txReceipt.blockNumber}`);
    deployments.set("PoolUtil", poolUtil.address);
    deployments.set("FundingRateUtil", fundingRateUtil.address);
    deployments.set("PriceUtil", priceUtil.address);
    deployments.set("PositionUtil", positionUtil.address);
    deployments.set("LiquidityPositionUtil", liquidityPositionUtil.address);

    await initializePoolByteCode(
        poolUtil.address,
        fundingRateUtil.address,
        priceUtil.address,
        positionUtil.address,
        liquidityPositionUtil.address
    );

    const [deployer] = await ethers.getSigners();
    let nonce = await deployer.getTransactionCount();
    console.log(`deployer address: ${deployer.address}, nonce: ${nonce}`);

    // token addresses
    const equAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    const veEQUAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    const efcAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    // plugin addresses
    const routerAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    const rewardCollectorAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    const orderBookAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    const positionRouterAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    // price feed address
    const priceFeedAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    // reward farm address
    const rewardFarmAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    // fee distributor address
    const feeDistributorAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    // pool factory address
    const poolFactoryAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    // mixed executor address
    const mixedExecutorAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    // executor assistant address
    const executorAssistantAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});
    // liquidator address
    const liquidatorAddr = ethers.utils.getContractAddress({from: deployer.address, nonce: nonce++});

    deployments.set("EQU", equAddr);
    deployments.set("veEQU", veEQUAddr);
    deployments.set("EFC", efcAddr);
    deployments.set("Router", routerAddr);
    deployments.set("RewardCollector", rewardCollectorAddr);
    deployments.set("OrderBook", orderBookAddr);
    deployments.set("PositionRouter", positionRouterAddr);
    deployments.set("PriceFeed", priceFeedAddr);
    deployments.set("RewardFarm", rewardFarmAddr);
    deployments.set("FeeDistributor", feeDistributorAddr);
    deployments.set("PoolFactory", poolFactoryAddr);
    deployments.set("MixedExecutor", mixedExecutorAddr);
    deployments.set("ExecutorAssistant", executorAssistantAddr);
    deployments.set("Liquidator", liquidatorAddr);

    // deploy tokens
    const EQU = await ethers.getContractFactory("EQU");
    const equ = await EQU.deploy();
    await equ.deployed();
    expectAddr(equ.address, equAddr);
    console.log(`EQU deployed to: ${equ.address}`);

    const VeEQU = await ethers.getContractFactory("veEQU");
    const veEQU = await VeEQU.deploy();
    await veEQU.deployed();
    expectAddr(veEQU.address, veEQUAddr);
    console.log(`veEQU deployed to: ${veEQU.address}`);

    const EFC = await ethers.getContractFactory("EFC");
    const efc = await EFC.deploy(100, 100, 100, rewardFarmAddr, feeDistributorAddr);
    await efc.deployed();
    expectAddr(efc.address, efcAddr);
    console.log(`EFC deployed to: ${efc.address}`);

    // deploy plugins
    const Router = await ethers.getContractFactory("Router");
    const router = await Router.deploy(efc.address, rewardFarmAddr, feeDistributorAddr);
    await router.deployed();
    expectAddr(router.address, routerAddr);
    console.log(`Router deployed to: ${router.address}`);

    const RewardCollector = await ethers.getContractFactory("RewardCollector");
    const rewardCollector = await RewardCollector.deploy(routerAddr, equ.address, efc.address);
    await rewardCollector.deployed();
    expectAddr(rewardCollector.address, rewardCollectorAddr);
    console.log(`RewardCollector deployed to: ${rewardCollector.address}`);

    const OrderBook = await ethers.getContractFactory("OrderBook");
    const orderBook = await OrderBook.deploy(network.usd, routerAddr, network.minOrderBookExecutionFee);
    await orderBook.deployed();
    expectAddr(orderBook.address, orderBookAddr);
    console.log(`OrderBook deployed to: ${orderBook.address}`);

    const PositionRouter = await ethers.getContractFactory("PositionRouter");
    const positionRouter = await PositionRouter.deploy(network.usd, routerAddr, network.minPositionRouterExecutionFee);
    await positionRouter.deployed();
    expectAddr(positionRouter.address, positionRouterAddr);
    console.log(`PositionRouter deployed to: ${positionRouter.address}`);

    // deploy price feed
    const PriceFeed = await ethers.getContractFactory("PriceFeed");
    const priceFeed = await PriceFeed.deploy(network.usdChainLinkPriceFeed, 0);
    await priceFeed.deployed();
    expectAddr(priceFeed.address, priceFeedAddr);
    console.log(`PriceFeed deployed to: ${priceFeed.address}`);

    // deploy reward farm
    const RewardFarm = await ethers.getContractFactory("RewardFarm");
    const rewardFarm = await RewardFarm.deploy(
        poolFactoryAddr,
        routerAddr,
        efc.address,
        equ.address,
        network.farmMintTime,
        110_000_000n
    );
    await rewardFarm.deployed();
    expectAddr(rewardFarm.address, rewardFarmAddr);
    console.log(`RewardFarm deployed to: ${rewardFarm.address}`);

    // deploy fee distributor
    const FeeDistributor = await ethers.getContractFactory("FeeDistributor");
    const feeDistributor = await FeeDistributor.deploy(
        efc.address,
        equ.address,
        network.weth,
        veEQU.address,
        network.usd,
        routerAddr,
        network.uniswapV3Factory,
        network.uniswapV3PositionManager,
        7
    );
    await feeDistributor.deployed();
    expectAddr(feeDistributor.address, feeDistributorAddr);
    console.log(`FeeDistributor deployed to: ${feeDistributor.address}`);

    // deploy pool factory
    const PoolFactory = await ethers.getContractFactory("PoolFactory");
    const poolFactory = await PoolFactory.deploy(
        network.usd,
        efc.address,
        routerAddr,
        priceFeedAddr,
        feeDistributorAddr,
        rewardFarmAddr
    );
    await poolFactory.deployed();
    expectAddr(poolFactory.address, poolFactoryAddr);
    console.log(`PoolFactory deployed to: ${poolFactory.address}`);

    // deploy mixed executor
    const MixedExecutor = await ethers.getContractFactory("MixedExecutor");
    const mixedExecutor = await MixedExecutor.deploy(liquidatorAddr, positionRouterAddr, priceFeedAddr, orderBookAddr);
    await mixedExecutor.deployed();
    expectAddr(mixedExecutor.address, mixedExecutorAddr);
    console.log(`MixedExecutor deployed to: ${mixedExecutor.address}`);

    // deploy executor assistant
    const ExecutorAssistant = await ethers.getContractFactory("ExecutorAssistant");
    const executorAssistant = await ExecutorAssistant.deploy(positionRouterAddr);
    await executorAssistant.deployed();
    expectAddr(executorAssistant.address, executorAssistantAddr);
    console.log(`ExecutorAssistant deployed to: ${executorAssistant.address}`);

    // deploy liquidator
    const Liquidator = await ethers.getContractFactory("Liquidator");
    const liquidator = await Liquidator.deploy(routerAddr, poolFactoryAddr, network.usd, efc.address);
    await liquidator.deployed();
    expectAddr(liquidator.address, liquidatorAddr);
    console.log(`Liquidator deployed to: ${liquidator.address}`);

    // initialize tokens
    await equ.setMinter(rewardFarmAddr, true);
    await (veEQU as MultiMinter).setMinter(feeDistributor.address, true);
    await efc.setBaseURI(network.efcBaseURL);
    console.log("Initialize tokens finished");

    // initialize plugins
    await router.registerLiquidator(liquidatorAddr);
    await router.registerPlugin(rewardCollectorAddr);
    await router.registerPlugin(orderBookAddr);
    await router.registerPlugin(positionRouterAddr);
    await orderBook.updateOrderExecutor(mixedExecutorAddr, true);
    await positionRouter.updatePositionExecutor(mixedExecutorAddr, true);
    console.log("Initialize plugins finished");

    // initialize price feed
    await priceFeed.setUpdater(mixedExecutorAddr, true);
    await priceFeed.setUpdater(deployer.address, true);
    if (network.sequencerUpTimeFeed != undefined) {
        await priceFeed.setSequencerUptimeFeed(network.sequencerUpTimeFeed);
    }
    for (let item of network.tokens) {
        await priceFeed.setRefPriceFeed(item.address, item.chainLinkPriceFeed);
        await priceFeed.setMaxCumulativeDeltaDiffs(item.address, item.maxCumulativeDeltaDiff);
    }
    // await priceFeed.setPriceX96s(
    //     network.tokens.map((item) => item.address),
    //     network.tokens.map(
    //         (item) => BigInt(new Decimal(item.price).mul(new Decimal(2).pow(96)).toFixed(0)) / 10n ** 12n
    //     ),
    //     Math.floor(new Date().getTime() / 1000)
    // );
    console.log("Initialize price feed finished");

    // initialize fee distributor
    await feeDistributor.setLockupRewardMultipliers([
        {
            period: 30,
            multiplier: 1,
        },
        {
            period: 60,
            multiplier: 2,
        },
        {
            period: 90,
            multiplier: 3,
        },
    ]);

    // initialize pool factory
    await concatPoolCreationCode(poolFactory);
    await poolFactory.grantRole(
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ROLE_POSITION_LIQUIDATOR")),
        liquidatorAddr
    );
    await poolFactory.grantRole(
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ROLE_LIQUIDITY_POSITION_LIQUIDATOR")),
        liquidatorAddr
    );
    console.log("Initialize pool factory finished");

    // initialize mixed executor
    await mixedExecutor.setTokens(network.tokens.map((item) => item.address));
    for (let item of network.mixedExecutors) {
        await mixedExecutor.setExecutor(item, true);
    }
    console.log("Initialize mixed executor finished");

    // initialize liquidator
    await liquidator.updateExecutor(mixedExecutorAddr, true);
    console.log("Initialize liquidator finished");

    // write deployments to file
    const deploymentsOutput = {
        block: txReceipt.blockNumber,
        usd: network.usd,
        poolBytecodeHash: getPoolBytecodeHash(),
        deployments: Object.fromEntries(deployments),
    };
    const fs = require("fs");
    if (!fs.existsSync("deployments")) {
        fs.mkdirSync("deployments");
    }
    const chainId = (await poolUtil.provider.getNetwork()).chainId;
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(deploymentsOutput));
    console.log(`deployments output to deployments/${chainId}.json`);

    console.log(`
    The following scripts need to be executed:
        1. Register Pools - registerPools.ts
        2. Update Reward Farm - updateRewardFarm.ts
        3. Deploy Position Farm Reward Distributor - deployPositionFarmRewardDistributor.ts
        4. Deploy Reward Collector V2 - deployRewardCollectorV2.ts
        5. Deploy Pool Indexer - deployPoolIndexer.ts
        6. Assign Pool Index - registerPools.ts (incremental update)
        7. Dereigster Position Farm Reward Distributor - deregisterPositionFarmRewardDistributor.ts 
        8. Deploy Farm Reward Distributor V2 - deployFarmRewardDistributorV2.ts
        9. Deploy Reward Collector V3 - deployRewardCollectorV3.ts
        10. Deploy Order Book Assistant - deployOrderBookAssistant.ts
        11. Deploy Mixed Executor V2 - deployMixedExecutorV2.ts
    `);
}

function expectAddr(actual: string, expected: string) {
    if (actual != expected) {
        throw new Error(`actual address ${actual} is not equal to expected address ${expected}`);
    }
}

async function deployLibraries() {
    const PoolUtil = await ethers.getContractFactory("PoolUtil");
    const poolUtil = await PoolUtil.deploy();
    await poolUtil.deployed();
    console.log(`PoolUtil deployed to: ${poolUtil.address}`);

    const FundingRateUtil = await ethers.getContractFactory("FundingRateUtil");
    const fundingRateUtil = await FundingRateUtil.deploy();
    await fundingRateUtil.deployed();
    console.log(`FundingRateUtil deployed to: ${fundingRateUtil.address}`);

    const PriceUtil = await ethers.getContractFactory("PriceUtil");
    const priceUtil = await PriceUtil.deploy();
    await priceUtil.deployed();
    console.log(`PriceUtil deployed to: ${priceUtil.address}`);

    const PositionUtil = await ethers.getContractFactory("PositionUtil");
    const positionUtil = await PositionUtil.deploy();
    await positionUtil.deployed();
    console.log(`PositionUtil deployed to: ${positionUtil.address}`);

    const LiquidityPositionUtil = await ethers.getContractFactory("LiquidityPositionUtil");
    const liquidityPositionUtil = await LiquidityPositionUtil.deploy();
    await liquidityPositionUtil.deployed();
    console.log(`LiquidityPositionUtil deployed to: ${liquidityPositionUtil.address}`);

    return {poolUtil, fundingRateUtil, priceUtil, positionUtil, liquidityPositionUtil};
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
