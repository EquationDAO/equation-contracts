import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const OrderBookAssistant = await ethers.getContractFactory("OrderBookAssistant");
    const orderBookAssistant = await OrderBookAssistant.deploy(document.deployments.OrderBook);
    await orderBookAssistant.deployed();
    console.log(`OrderBookAssistant deployed to: ${orderBookAssistant.address}`);

    document.deployments.OrderBookAssistant = orderBookAssistant.address;

    const fs = require("fs");
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(document));

    const orderBook = await ethers.getContractAt("OrderBook", document.deployments.OrderBook);
    await orderBook.updateOrderExecutor(orderBookAssistant.address, true);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
