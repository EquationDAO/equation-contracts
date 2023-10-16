import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const MixedExecutor = await ethers.getContractFactory("MixedExecutor");
    const mixedExecutor = await MixedExecutor.deploy(
        document.deployments.Liquidator,
        document.deployments.PositionRouter,
        document.deployments.PriceFeed,
        document.deployments.OrderBook
    );
    await mixedExecutor.setTokens(network.tokens.map((item) => item.address));

    for (let item of network.mixedExecutors) {
        await mixedExecutor.setExecutor(item, true);
    }

    // register mixed executor to pool factory
    const PoolFactory = await ethers.getContractAt("PoolFactory", document.deployments.PoolFactory);
    await PoolFactory.grantRole(
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ROLE_POSITION_LIQUIDATOR")),
        mixedExecutor.address
    );
    await PoolFactory.grantRole(
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes("ROLE_LIQUIDITY_POSITION_LIQUIDATOR")),
        mixedExecutor.address
    );

    // register mixed executor to order book
    const OrderBook = await ethers.getContractAt("OrderBook", document.deployments.OrderBook);
    await OrderBook.updateOrderExecutor(mixedExecutor.address, true);

    // register mixed executor to position router
    const PositionRouter = await ethers.getContractAt("PositionRouter", document.deployments.PositionRouter);
    await PositionRouter.updatePositionExecutor(mixedExecutor.address, true);

    // register mixed executor to price feed
    const PriceFeed = await ethers.getContractAt("PriceFeed", document.deployments.PriceFeed);
    await PriceFeed.setUpdater(mixedExecutor.address, true);

    document.deployments.MixedExecutor = mixedExecutor.address;
    const fs = require("fs");
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(document));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
