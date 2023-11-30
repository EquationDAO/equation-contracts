import "dotenv/config";
import {networks} from "../networks";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [
    `${document.deployments.EFC}`,
    `${document.deployments.EQU}`,
    networks[process.env.CHAIN_NAME as keyof typeof networks].weth,
    `${document.deployments.veEQU}`,
    `${document.usd}`,
    `${document.deployments.Router}`,
    networks[process.env.CHAIN_NAME as keyof typeof networks].uniswapV3Factory,
    networks[process.env.CHAIN_NAME as keyof typeof networks].uniswapV3PositionManager,
    7,
];
