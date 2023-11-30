import {networks} from "../networks";

module.exports = [networks[process.env.CHAIN_NAME as keyof typeof networks].usdChainLinkPriceFeed, 0];
