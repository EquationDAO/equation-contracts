let usings = [`packAddress`, "unpackAddress", `packBool`, `unpackBool`];
let functions = [];
for (let bits = 8; bits <= 248; bits += 8) {
    usings.push(`packUint${bits}`, `unpackUint${bits}`);

    functions.push(`
    function packUint${bits}(PackedValue self, uint${bits} value, uint8 position) pure returns (PackedValue) {
        return PackedValue.wrap(PackedValue.unwrap(self) | (uint256(value) << position));
    }    
    `);

    functions.push(`
    function unpackUint${bits}(PackedValue self, uint8 position) pure returns (uint${bits}) {
        return uint${bits}((PackedValue.unwrap(self) >> position) & 0x${
        (bits == 160 ? "00" : "") + "ff".repeat(bits / 8)
    });
    }    
    `);
}

functions.push(`
function packBool(PackedValue self, bool value, uint8 position) pure returns (PackedValue) {
    return packUint8(self, value ? 1 : 0, position);
}

function unpackBool(PackedValue self, uint8 position) pure returns (bool) {
    return ((PackedValue.unwrap(self) >> position) & 0x1) == 1;
}

function packAddress(PackedValue self, address value, uint8 position) pure returns (PackedValue) {
    return packUint160(self, uint160(value), position);
}

function unpackAddress(PackedValue self, uint8 position) pure returns (address) {
    return address(unpackUint160(self, position));
}
`);

const template = `
// This file was procedurally generated from scripts/generate/PackedValue.template.js, DO NOT MODIFY MANUALLY
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

type PackedValue is uint256;

using {
    ${usings.join(`,\n`)}
} for PackedValue global;

${functions.join(`\n`)}
`;

const fs = require("fs");
fs.writeFileSync("./contracts/types/PackedValue.sol", template);
