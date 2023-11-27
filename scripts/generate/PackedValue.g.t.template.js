let functions = [];
for (let bits = 8; bits <= 248; bits += 8) {
    const targetBits = 256 - bits;
    functions.push(`
    function test_uint${bits}_and_uint${targetBits}(uint${bits} value1, uint${targetBits} value2) public {
        PackedValue packed = PackedValue.wrap(0);
        packed = packed.packUint${bits}(value1, 0);
        packed = packed.packUint${targetBits}(value2, ${bits});

        assertEq(packed.unpackUint${bits}(0), value1);
        assertEq(packed.unpackUint${targetBits}(${bits}), value2);
    }
    `);
}

const template = `
// This file was procedurally generated from scripts/generate/PackedValue.g.t.template.js, DO NOT MODIFY MANUALLY
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../../contracts/types/PackedValue.sol";

contract PackedValueTest_Generated is Test {

${functions.join(`\n`)}

}
`;

const fs = require("fs");
fs.writeFileSync("./test/foundry/PackedValue.g.t.sol", template);
