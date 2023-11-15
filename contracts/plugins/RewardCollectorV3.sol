// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import "./RewardCollector.sol";
import "../farming/FarmRewardDistributorV2.sol";

/// @custom:since v0.0.3
contract RewardCollectorV3 is RewardCollector {
    FarmRewardDistributorV2 public immutable distributorV2;

    constructor(
        Router _router,
        IERC20 _EQU,
        IEFC _EFC,
        FarmRewardDistributorV2 _distributorV2
    ) RewardCollector(_router, _EQU, _EFC) {
        distributorV2 = _distributorV2;
    }

    function collectFarmRewardBatch(
        PackedValue _nonceAndLockupPeriod,
        PackedValue[] calldata _packedPoolRewardValues,
        bytes calldata _signature,
        address _receiver
    ) external virtual {
        distributorV2.collectBatch(msg.sender, _nonceAndLockupPeriod, _packedPoolRewardValues, _signature, _receiver);
    }
}
