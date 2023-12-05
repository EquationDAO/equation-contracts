import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const TokenVertexUpdaterGovernor = await ethers.getContractFactory("TokenVertexUpdaterGovernor");
    const [admin] = await ethers.getSigners();
    const governor = await TokenVertexUpdaterGovernor.deploy(
        admin.address,
        admin.address,
        document.deployments.PoolFactory
    );
    await governor.deployed();
    console.log(`TokenVertexUpdaterGovernor deployed to: ${governor.address}`);

    document.deployments.TokenVertexUpdaterGovernor = governor.address;

    const fs = require("fs");
    fs.writeFileSync(`deployments/${chainId}.json`, JSON.stringify(document));

    const poolFactory = await ethers.getContractAt("PoolFactory", document.deployments.PoolFactory);
    await poolFactory.changeGov(governor.address);
    await governor.execute(poolFactory.address, 0n, poolFactory.interface.encodeFunctionData("acceptGov"));
    console.warn(`The permissions of PoolFactory is already transfer to ${governor.address}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
