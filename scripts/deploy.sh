#!/bin/bash
set -e

network=""
chainID=""
deployEnabled=false
verifyEnabled=false

usage() {
    echo "Usage: $0 [-n <network>] [-c <chain-id>] [-d] [-v]" 1>&2
    echo "  -n <network>    Network to deploy to" 1>&2
    echo "  -c <chain-id>   ChainID of the network" 1>&2
    echo "  -d true/false   Whether to deploy contracts" 1>&2
    echo "  -v true/false   Whether to verify contracts" 1>&2
    exit 1
}

deploy() {
    echo "Deploying to ${network} with chainID ${chainID}"
    set -x
    npx hardhat run ./scripts/index.ts --network ${network}
    npx hardhat run ./scripts/registerPools.ts --network ${network}
    npx hardhat run ./scripts/updateRewardFarm.ts --network ${network}
    npx hardhat run ./scripts/deployPositionFarmRewardDistributor.ts --network ${network}
    npx hardhat run ./scripts/deployRewardCollectorV2.ts --network ${network}
    npx hardhat run ./scripts/deployPoolIndexer.ts --network ${network}
    npx hardhat run ./scripts/registerPools.ts --network ${network}
    npx hardhat run ./scripts/deregisterPositionFarmRewardDistributor.ts --network ${network}
    npx hardhat run ./scripts/deployFarmRewardDistributorV2.ts --network ${network}
    npx hardhat run ./scripts/deployRewardCollectorV3.ts --network ${network}
    npx hardhat run ./scripts/deployOrderBookAssistant.ts --network ${network}
    npx hardhat run ./scripts/deployMixedExecutorV2.ts --network ${network}
}

verify() {
    echo "Verifying on ${network} with chainID ${chainID}"
    set -x
    export CHAIN_NAME=${network}
    export CHAIN_ID=${chainID}
    npx hardhat verify --network ${network} `cat ./deployments/${chainID}.json|jq -r '.deployments.PoolUtil'`
    # Why is the bytecode of this contract different from the deployed bytecode?
    npx hardhat verify --network ${network} `cat ./deployments/${chainID}.json|jq -r '.deployments.FundingRateUtil'` || true
    npx hardhat verify --network ${network} `cat ./deployments/${chainID}.json|jq -r '.deployments.PriceUtil'` || true
    npx hardhat verify --network ${network} `cat ./deployments/${chainID}.json|jq -r '.deployments.PositionUtil'`
    npx hardhat verify --network ${network} `cat ./deployments/${chainID}.json|jq -r '.deployments.LiquidityPositionUtil'` || true
    npx hardhat verify --network ${network} `cat ./deployments/${chainID}.json|jq -r '.deployments.EQU'`
    npx hardhat verify --network ${network} `cat ./deployments/${chainID}.json|jq -r '.deployments.veEQU'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyEFC.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.EFC'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyRouter.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.Router'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyRewardCollector.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.RewardCollector'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyOrderBook.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.OrderBook'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyPositionRouter.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.PositionRouter'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyPriceFeed.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.PriceFeed'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyRewardFarm.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.RewardFarm'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyFeeDistributor.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.FeeDistributor'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyPoolFactory.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.PoolFactory'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyMixedExecutor.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.MixedExecutor'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyExecutorAssistant.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.ExecutorAssistant'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyLiquidator.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.Liquidator'`
    npx hardhat verify --network ${network} `cat ./deployments/${chainID}.json|jq -r '.deployments.registerPools[-1] | .pool'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyPositionFarmRewardDistributor.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.PositionFarmRewardDistributor'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyRewardCollectorV2.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.RewardCollectorV2'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyPoolIndexer.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.PoolIndexer'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyFarmRewardDistributorV2.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.FarmRewardDistributorV2'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyRewardCollectorV3.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.RewardCollectorV3'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyOrderBookAssistant.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.OrderBookAssistant'`
    npx hardhat verify --network ${network} --constructor-args scripts/verify/verifyMixedExecutorV2.ts `cat ./deployments/${chainID}.json|jq -r '.deployments.MixedExecutorV2'`
}

while getopts "n:c:d:v:" opt; do
  case $opt in
    n) network="$OPTARG"
    ;;
    c) chainID="$OPTARG"
    ;;
    d) deployEnabled="$OPTARG"
    ;;
    v) verifyEnabled="$OPTARG"
    ;;
    \?) usage
    ;;
  esac
done

if [ -z "$network" ]; then
    echo "Network is not set"
    usage
fi

if [ -z "$chainID" ]; then
    echo "ChainID is not set"
    usage
fi

if [ "$deployEnabled" = "true" ] ; then
    deploy
fi

if [ "$verifyEnabled" = "true" ] ; then
    verify
fi