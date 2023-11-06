import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    if (network.distributorSigner == undefined) {
        throw new Error(`network ${hardhatArguments.network} does not have a distributor signer`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const Distributor = await ethers.getContractFactory("PositionFarmRewardDistributor");
    const distributor = await Distributor.deploy(network.distributorSigner, document.deployments.EQU);
    await distributor.deployed();
    console.log(`PositionFarmRewardDistributor deployed to: ${distributor.address}`);

    document.deployments.PositionFarmRewardDistributor = distributor.address;

    const fs = require("fs");
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(document));

    // Set distributor as minter
    const EQU = await ethers.getContractAt("MultiMinter", document.deployments.EQU);
    await EQU.setMinter(distributor.address, true);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
