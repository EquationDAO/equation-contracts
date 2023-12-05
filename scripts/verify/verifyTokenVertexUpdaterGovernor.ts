import "dotenv/config";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [
    `0xe42E56cF9fDBe26da63689B2748c15c848d0bad4`,
    `0xe42E56cF9fDBe26da63689B2748c15c848d0bad4`,
    `${document.deployments.PoolFactory}`,
];
