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
        "0xcef39F8e826f650a8934C8E29251632600A0e11c",
        "0x558EB86782EC6456894b5e7e9dC9356e1396f2e8",
        "0x65e1B154c6b066dcE209669506c05bDD2B56C70f",
        "0x0d4e02EDcC3EB6f927675413bD12214Ed6348a4b",
        "0x3B70C25e6aA2e3F58aBE5F64EE66a858cfD9590B",
        "0xf1661E4FCe84054ddD857f28Fe2fB772a1444724",
        "0x94721a19Cd9A55fbcBd9246f405D9FAFb08d21C8",
        "0x3f08bb3A44A2B9DFa1Eb14C056c44B33dC9Ae8b5",
    ]);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
