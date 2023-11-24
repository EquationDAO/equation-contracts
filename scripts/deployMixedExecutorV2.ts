import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const MixedExecutorV2 = await ethers.getContractFactory("MixedExecutorV2");
    const mixedExecutorV2 = await MixedExecutorV2.deploy(
        document.deployments.PoolIndexer,
        document.deployments.Liquidator,
        document.deployments.PositionRouter,
        document.deployments.PriceFeed,
        document.deployments.OrderBook
    );
    await mixedExecutorV2.deployed();
    console.log(`MixedExecutorV2 deployed to: ${mixedExecutorV2.address}`);

    document.deployments.MixedExecutorV2 = mixedExecutorV2.address;

    const fs = require("fs");
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(document));

    const priceFeed = await ethers.getContractAt("PriceFeed", document.deployments.PriceFeed);
    await priceFeed.setUpdater(mixedExecutorV2.address, true);

    const orderBook = await ethers.getContractAt("OrderBook", document.deployments.OrderBook);
    await orderBook.updateOrderExecutor(mixedExecutorV2.address, true);

    const positionRouter = await ethers.getContractAt("PositionRouter", document.deployments.PositionRouter);
    await positionRouter.updatePositionExecutor(mixedExecutorV2.address, true);

    const liquidator = await ethers.getContractAt("Liquidator", document.deployments.Liquidator);
    await liquidator.updateExecutor(mixedExecutorV2.address, true);

    for (let item of network.mixedExecutors) {
        await mixedExecutorV2.setExecutor(item, true);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
