import "dotenv/config";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [
    `${document.usd}`,
    `${document.deployments.EFC}`,
    `${document.deployments.Router}`,
    `${document.deployments.PriceFeed}`,
    `${document.deployments.FeeDistributor}`,
    `${document.deployments.RewardFarm}`,
];
