import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const PoolIndexer = await ethers.getContractFactory("PoolIndexer");
    const poolIndexer = await PoolIndexer.deploy(document.deployments.PoolFactory);
    await poolIndexer.deployed();
    console.log(`PoolIndexer deployed to: ${poolIndexer.address}`);

    document.deployments.PoolIndexer = poolIndexer.address;

    const fs = require("fs");
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(document));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
