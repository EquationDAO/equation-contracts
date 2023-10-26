import "dotenv/config";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [
    `${document.deployments.EFC}`,
    `${document.deployments.RewardFarm}`,
    `${document.deployments.FeeDistributor}`,
];
