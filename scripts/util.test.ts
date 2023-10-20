import {expect} from "chai";
import {parsePercent} from "./util";

describe("util", () => {
    describe("#parsePercent", () => {
        const tests = [
            {
                input: "0%",
                expected: 0n,
            },
            {
                input: "0.001%",
                expected: 1_000n,
            },
            {
                input: "0.01%",
                expected: 10_000n,
            },
            {
                input: "0.1%",
                expected: 100_000n,
            },
            {
                input: "1%",
                expected: 1_000_000n,
            },
            {
                input: "10%",
                expected: 10_000_000n,
            },
            {
                input: "50%",
                expected: 50_000_000n,
            },
            {
                input: "100%",
                expected: 100_000_000n,
            },
        ];
        for (let test of tests) {
            it(`parse percent of ${test.input} should equal to ${test.expected}`, () => {
                expect(parsePercent(test.input)).to.eq(test.expected);
            });
        }
    });
});
