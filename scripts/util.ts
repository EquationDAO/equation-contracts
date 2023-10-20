import Decimal from "decimal.js";

export function parsePercent(val: string): bigint {
    if (!val.endsWith("%")) {
        throw new Error("invalid percent, should end with %");
    }
    val = val.slice(0, -1);
    return BigInt(new Decimal(val).mul(new Decimal(1e6)).toFixed(0));
}
