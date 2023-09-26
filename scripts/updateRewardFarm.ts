import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);

    const RewardFarm = await ethers.getContractAt("RewardFarm", document.deployments.RewardFarm);
    await RewardFarm.setConfig({
        liquidityRate: 28_000_000n, // 28%
        riskBufferFundLiquidityRate: 50_000_000n, // 50%
        referralTokenRate: 20_000_000n, // 20%
        referralParentTokenRate: 2_000_000n, // 2%
    });

    await RewardFarm.setPoolsReward(
        document.deployments.registerPools.map((item: {pool: any}) => item.pool),
        network.tokens.map((item) => item.rewardsPerSecond)
    );
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
