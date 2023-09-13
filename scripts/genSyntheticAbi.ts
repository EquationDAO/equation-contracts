import {writeFileSync} from "fs";
import {abi as PoolAbi} from "../artifacts/contracts/core/Pool.sol/Pool.json";
import {abi as FundingRateUtilAbi} from "../artifacts/contracts/libraries/FundingRateUtil.sol/FundingRateUtil.json";
import {abi as PriceUtilAbi} from "../artifacts/contracts/libraries/PriceUtil.sol/PriceUtil.json";

async function main() {
    const events = new Set<string>(PoolAbi.filter((x) => x.type == "event").map((x) => x.name!));
    const abi = [
        ...PoolAbi,
        ...PriceUtilAbi.filter((x) => x.type == "event" && !events.has(x.name)),
        ...FundingRateUtilAbi.filter((x) => x.type == "event" && !events.has(x.name)),
    ];
    writeFileSync("artifacts/contracts/core/Pool.sol/Pool.synthetic.json", JSON.stringify(abi, null, 2));
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
