import "dotenv/config";
import {networks} from "../networks";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [
    `${document.deployments.PoolFactory}`,
    `${document.deployments.Router}`,
    `${document.deployments.EFC}`,
    `${document.deployments.EQU}`,
    networks[process.env.CHAIN_NAME as keyof typeof networks].farmMintTime,
    110_000_000n,
];
