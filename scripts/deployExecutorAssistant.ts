import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const ExecutorAssistant = await ethers.getContractFactory("ExecutorAssistant");
    const executorAssistant = await ExecutorAssistant.deploy(document.deployments.PositionRouter);
    await executorAssistant.deployed();

    document.deployments.ExecutorAssistant = executorAssistant.address;
    const fs = require("fs");
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(document));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
