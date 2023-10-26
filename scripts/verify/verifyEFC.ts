import "dotenv/config";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [100, 100, 100, `${document.deployments.RewardFarm}`, `${document.deployments.FeeDistributor}`];
