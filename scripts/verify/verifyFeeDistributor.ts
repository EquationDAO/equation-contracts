import "dotenv/config";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [
    `${document.deployments.EFC}`,
    `${document.deployments.EQU}`,
    `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1`,
    `${document.deployments.veEQU}`,
    `${document.usd}`,
    `${document.deployments.Router}`,
    `0x1F98431c8aD98523631AE4a59f267346ea31F984`,
    `0xC36442b4a4522E871399CD717aBDD847Ab11FE88`,
    7,
];
