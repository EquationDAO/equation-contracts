import "dotenv/config";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [
    `${document.deployments.PoolIndexer}`,
    `${document.deployments.Liquidator}`,
    `${document.deployments.PositionRouter}`,
    `${document.deployments.PriceFeed}`,
    `${document.deployments.OrderBook}`,
];
