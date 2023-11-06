import "dotenv/config";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [`0x2288A79e5EFA061719EDaF8C69968c6e166ce322`, `${document.deployments.EQU}`];
