import {ethers, hardhatArguments} from "hardhat";
import {networks} from "./networks";
import {computePoolAddress, setBytecodeHash} from "../test/shared/address";
import {token} from "../typechain-types/@openzeppelin/contracts";

async function main() {
    const network = networks[hardhatArguments.network as keyof typeof networks];
    if (network == undefined) {
        throw new Error(`network ${hardhatArguments.network} is not defined`);
    }
    const chainId = (await ethers.provider.getNetwork()).chainId;
    const document = require(`../deployments/${chainId}.json`);
    setBytecodeHash(document.poolBytecodeHash);

    const poolFactory = await ethers.getContractAt("PoolFactory", document.deployments.PoolFactory);
    const blockNumber = await poolFactory.provider.getBlockNumber();
    for (let item of network.tokens) {
        const enabled = await poolFactory.isEnabledToken(item.address);
        if (!enabled) {
            continue;
        }

        const poolAddr = computePoolAddress(poolFactory.address, item.address, network.usd);
        console.log(`updating ${item.name} (${item.address}) at ${poolAddr}`);
        let tokenCfg = await poolFactory.tokenConfigs(item.address, {blockTag: blockNumber});
        let tokenCfgAfter = {
            ...tokenCfg,
            maxLeveragePerLiquidityPosition: 100,
        };
        console.log(tokenCfgAfter);
        let tokenFeeCfg = await poolFactory.tokenFeeRateConfigs(item.address, {blockTag: blockNumber});
        let vertices = [
            {balanceRate: 0n, premiumRate: 0n},
            await poolFactory.tokenPriceVertexConfigs(item.address, 1, {blockTag: blockNumber}),
            await poolFactory.tokenPriceVertexConfigs(item.address, 2, {blockTag: blockNumber}),
            await poolFactory.tokenPriceVertexConfigs(item.address, 3, {blockTag: blockNumber}),
            await poolFactory.tokenPriceVertexConfigs(item.address, 4, {blockTag: blockNumber}),
            await poolFactory.tokenPriceVertexConfigs(item.address, 5, {blockTag: blockNumber}),
            await poolFactory.tokenPriceVertexConfigs(item.address, 6, {blockTag: blockNumber}),
        ];
        let tokenPriceCfg = await poolFactory.tokenPriceConfigs(item.address, {blockTag: blockNumber});
        let calldata = poolFactory.interface.encodeFunctionData("updateTokenConfig", [
            item.address,
            tokenCfgAfter,
            tokenFeeCfg,
            {
                maxPriceImpactLiquidity: tokenPriceCfg.maxPriceImpactLiquidity,
                liquidationVertexIndex: tokenPriceCfg.liquidationVertexIndex,
                vertices: vertices,
            },
        ]);

        const governor = await ethers.getContractAt(
            "TokenVertexUpdaterGovernor",
            document.deployments.TokenVertexUpdaterGovernor
        );
        await governor.execute(poolFactory.address, 0n, calldata);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
