import {expect, use} from "chai";
import {jestSnapshotPlugin} from "mocha-chai-jest-snapshot";
import type {BigNumber, ContractTransaction} from "ethers";

use(jestSnapshotPlugin());

export async function expectSnapshotGasCost(call: Promise<BigNumber | ContractTransaction>) {
    const ans = await call;
    if (isBigNumber(ans)) {
        expect(ans.toNumber()).toMatchSnapshot();
    } else {
        const receipt = await ans.wait();
        expect(receipt.gasUsed.toNumber()).toMatchSnapshot();
    }
}

function isBigNumber(value: BigNumber | ContractTransaction): value is BigNumber {
    return (value as BigNumber).add != undefined;
}
