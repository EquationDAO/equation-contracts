import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const RewardCollectorV2 = await ethers.getContractFactory("RewardCollectorV2");
    const rewardCollectorV2 = await RewardCollectorV2.deploy(
        document.deployments.Router,
        document.deployments.EQU,
        document.deployments.EFC,
        document.deployments.PositionFarmRewardDistributor
    );
    await rewardCollectorV2.deployed();
    console.log(`RewardCollectorV2 deployed to: ${rewardCollectorV2.address}`);

    document.deployments.RewardCollectorV2 = rewardCollectorV2.address;

    const fs = require("fs");
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(document));

    // Register collector
    const distributor = await ethers.getContractAt(
        "PositionFarmRewardDistributor",
        document.deployments.PositionFarmRewardDistributor
    );
    await distributor.setCollector(rewardCollectorV2.address, true);

    // Register plugin
    const router = await ethers.getContractAt("Router", document.deployments.Router);
    await router.registerPlugin(rewardCollectorV2.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
