import "dotenv/config";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [
    `${document.deployments.PoolFactory}`,
    `${document.deployments.Router}`,
    `${document.deployments.EFC}`,
    `${document.deployments.EQU}`,
    Math.floor(new Date("2023-10-28T00:00:00.000Z").getTime() / 1000),
    110_000_000n,
];
