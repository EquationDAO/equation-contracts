import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";
import {computePoolAddress, setBytecodeHash} from "../test/shared/address";
import {Pool, PoolIndexer} from "../typechain-types";

export async function registerPools(chainId: number) {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const document = require(`../deployments/${chainId}.json`);
    setBytecodeHash(document.poolBytecodeHash);

    const poolFactory = await ethers.getContractAt("PoolFactory", document.deployments.PoolFactory);
    let poolIndexer: undefined | PoolIndexer;
    if (document.deployments.PoolIndexer != undefined) {
        poolIndexer = await ethers.getContractAt("PoolIndexer", document.deployments.PoolIndexer);
    }
    for (let item of network.tokens) {
        const enabled = await poolFactory.isEnabledToken(item.address);
        if (enabled) {
            if ((await poolIndexer?.tokenIndexes(item.address)) === 0) {
                await poolIndexer?.assignPoolIndex(poolFactory.pools(item.address));
            }
            continue;
        }

        const poolAddr = computePoolAddress(poolFactory.address, item.address, network.usd);
        console.log(`registering ${item.name} (${item.address}) at ${poolAddr}`);
        await poolFactory.enableToken(item.address, item.tokenCfg, item.tokenFeeCfg, item.tokenPriceCfg);
        await poolFactory.createPool(item.address);
        await poolIndexer?.assignPoolIndex(poolAddr);
        if (document.deployments.registerPools == undefined) {
            document.deployments.registerPools = [];
        }
        document.deployments.registerPools.push({
            name: item.name,
            token: item.address,
            pool: computePoolAddress(poolFactory.address, item.address, network.usd),
        });
    }

    const fs = require("fs");
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(document));
}

async function main() {
    await registerPools((await ethers.provider.getNetwork()).chainId);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
