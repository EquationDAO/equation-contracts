import "dotenv/config";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [
    `${document.deployments.Router}`,
    `${document.deployments.PoolFactory}`,
    `${document.usd}`,
    `${document.deployments.EFC}`,
];
