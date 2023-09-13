// add gas-price option to run task
task("run")
    .addOptionalParam("gasPrice", "Use specified gas price for all transactions, in gwei")
    .setAction(async (args, hre, runSuper) => {
        const {gasPrice} = args;
        if (gasPrice != undefined) {
            hre.network.config.gasPrice = ethers.utils.parseUnits(gasPrice, "gwei").toNumber();
        }
        await runSuper(args);
    });
