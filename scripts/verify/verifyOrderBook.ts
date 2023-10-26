import "dotenv/config";
import {ethers} from "hardhat";

const document = require(`../../deployments/${process.env.CHAIN_ID}.json`);

module.exports = [`${document.usd}`, `${document.deployments.Router}`, ethers.utils.parseUnits("0.0003", "ether")];
