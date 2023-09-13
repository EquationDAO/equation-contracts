import Decimal from "decimal.js";
import {BigNumber, BigNumberish} from "ethers";

export const Q64 = 1n << 64n;
export const Q96 = 1n << 96n;

export const BASIS_POINTS_DIVISOR = 100_000_000n;

export const DECIMALS_18: number = 18;
export const DECIMALS_6: number = 6;

export const PREMIUM_RATE_AVG_DENOMINATOR: bigint = 8n * 259560n;
export const PREMIUM_RATE_CLAMP_BOUNDARY_X96: bigint = 4951760157141521099596497n;

export const VERTEX_NUM: bigint = 7n;
export const LATEST_VERTEX = VERTEX_NUM - 1n;

export type Side = number;
export const SIDE_LONG: Side = 1;
export const SIDE_SHORT: Side = 2;

export function isLongSide(side: Side) {
    return side === SIDE_LONG;
}

export function isShortSide(side: Side) {
    return side === SIDE_SHORT;
}

export function flipSide(side: Side) {
    if (side === SIDE_LONG) {
        return SIDE_SHORT;
    } else if (side === SIDE_SHORT) {
        return SIDE_LONG;
    }
    return side;
}

export enum Rounding {
    Down,
    Up,
}

export function mulDiv(a: BigNumberish, b: BigNumberish, c: BigNumberish, rounding?: Rounding): bigint {
    const mul = BigNumber.from(a).mul(b);
    let ans = mul.div(c);
    if (rounding != undefined && rounding == Rounding.Up) {
        if (!ans.mul(c).eq(mul)) {
            ans = ans.add(1);
        }
    }
    return ans.toBigInt();
}

export function toX96(value: string): bigint {
    return BigInt(new Decimal(value).mul(new Decimal(2).pow(96)).toFixed(0));
}

export function toPriceX96(price: string, tokenDecimals: number, usdDecimals: number): bigint {
    return BigInt(
        new Decimal(price)
            .mul(new Decimal(10).pow(usdDecimals))
            .div(new Decimal(10).pow(tokenDecimals))
            .mul(new Decimal(2).pow(96))
            .toFixed(0)
    );
}
