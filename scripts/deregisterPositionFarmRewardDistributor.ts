import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const EQU = await ethers.getContractAt("MultiMinter", document.deployments.EQU);
    await EQU.setMinter(document.deployments.PositionFarmRewardDistributor, false);

    const distributor = await ethers.getContractAt(
        "PositionFarmRewardDistributor",
        document.deployments.PositionFarmRewardDistributor
    );
    await distributor.setCollector(document.deployments.RewardCollectorV2, false);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
