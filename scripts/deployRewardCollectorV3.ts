import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const RewardCollectorV3 = await ethers.getContractFactory("RewardCollectorV3");
    const rewardCollectorV3 = await RewardCollectorV3.deploy(
        document.deployments.Router,
        document.deployments.EQU,
        document.deployments.EFC,
        document.deployments.FarmRewardDistributorV2
    );
    await rewardCollectorV3.deployed();
    console.log(`RewardCollectorV3 deployed to: ${rewardCollectorV3.address}`);

    document.deployments.RewardCollectorV3 = rewardCollectorV3.address;

    const fs = require("fs");
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(document));

    // Register collector
    const distributor = await ethers.getContractAt(
        "FarmRewardDistributorV2",
        document.deployments.FarmRewardDistributorV2
    );
    await distributor.setCollector(rewardCollectorV3.address, true);

    // Register plugin
    const router = await ethers.getContractAt("Router", document.deployments.Router);
    await router.registerPlugin(rewardCollectorV3.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
