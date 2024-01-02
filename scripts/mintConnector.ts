import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const EFC = await ethers.getContractAt("EFC", document.deployments.EFC);
    await EFC.batchMintConnector([
        "0xeF1726E87eF7e7D6CD25C7AbFBbEdE91db002089",
        "0x65e1B154c6b066dcE209669506c05bDD2B56C70f",
        "0x69aD5697B8252526E6a177E53f91F2e2d65a8D9D",
        "0x27402892aBA80C5628a0837ee827FeC568c0d4BE",
        "0xf1661E4FCe84054ddD857f28Fe2fB772a1444724",
    ]);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
