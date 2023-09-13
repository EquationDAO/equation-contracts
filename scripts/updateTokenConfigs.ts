import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";
import {computePoolAddress, setBytecodeHash} from "../test/shared/address";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);
    setBytecodeHash(document.poolBytecodeHash);

    const poolFactory = await ethers.getContractAt("PoolFactory", document.deployments.PoolFactory);
    for (let item of network.tokens) {
        const enabled = await poolFactory.isEnabledToken(item.address);
        if (!enabled) {
            continue;
        }

        const poolAddr = computePoolAddress(poolFactory.address, item.address, network.usd);
        console.log(`updating ${item.name} (${item.address}) at ${poolAddr}`);
        await poolFactory.updateTokenConfig(item.address, item.tokenCfg, item.tokenFeeCfg, item.tokenPriceCfg);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
