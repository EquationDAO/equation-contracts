import "dotenv/config";
import {networks} from "../networks";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [
    `${document.usd}`,
    `${document.deployments.Router}`,
    networks[process.env.CHAIN_NAME as keyof typeof networks].minOrderBookExecutionFee,
];
