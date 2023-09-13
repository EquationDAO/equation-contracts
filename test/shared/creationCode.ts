import {getPoolBytecode} from "./address";
import {PoolFactory} from "../../typechain-types";
import {isHexPrefixed} from "hardhat/internal/hardhat-network/provider/utils/isHexPrefixed";

export async function concatPoolCreationCode(poolFactory: PoolFactory) {
    const bytes = hexToBytes(getPoolBytecode());
    const halfLen = Math.floor(bytes.length / 2);

    const firstHalf = bytes.slice(0, halfLen);
    await poolFactory.concatPoolCreationCode(false, firstHalf);

    const secondHalf = bytes.slice(halfLen);
    await poolFactory.concatPoolCreationCode(true, secondHalf);
}

function hexToBytes(hex: string) {
    if (isHexPrefixed(hex)) {
        hex = hex.substring(2);
    }
    let bytes = [];
    for (let c = 0; c < hex.length; c += 2) bytes.push(parseInt(hex.substr(c, 2), 16));
    return bytes;
}
