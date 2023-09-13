import {ethers} from "hardhat";

let bytecode: string;
let bytecodeHash: string;

export function getPoolBytecode(): string {
    return bytecode;
}

export function getPoolBytecodeHash(): string {
    return bytecodeHash;
}

export function setBytecodeHash(hash: string): void {
    bytecodeHash = hash;
}

export async function initializePoolByteCode(
    poolUtilAddress: string,
    fundingRateUtilAddress: string,
    priceUtilAddress: string,
    positionUtilAddress: string,
    liquidityPositionUtilAddress: string
): Promise<void> {
    const Pool = await ethers.getContractFactory("Pool", {
        libraries: {
            PoolUtil: poolUtilAddress,
            FundingRateUtil: fundingRateUtilAddress,
            PriceUtil: priceUtilAddress,
            PositionUtil: positionUtilAddress,
            LiquidityPositionUtil: liquidityPositionUtilAddress,
        },
    });

    bytecode = Pool.bytecode;
    bytecodeHash = ethers.utils.keccak256(bytecode);
}

export function computePoolAddress(poolFactory: string, token: string, usd: string): string {
    const encoded = ethers.utils.defaultAbiCoder.encode(["address", "address"], [token, usd]);
    return ethers.utils.getCreate2Address(poolFactory, ethers.utils.keccak256(encoded), bytecodeHash);
}
