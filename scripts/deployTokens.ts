import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }

    const ERC20 = await ethers.getContractFactory("ERC20");
    for (let item of network.tokens) {
        if (item.address != undefined) {
            continue;
        }

        const erc20 = await ERC20.deploy(`Equation Market - ${item.name}`, item.name);
        console.log(`deployed ${item.name} at ${erc20.address}`);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
