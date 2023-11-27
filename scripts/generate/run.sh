#!/usr/bin/bash

node ./scripts/generate/PackedValue.template.js

node ./scripts/generate/PackedValue.g.t.template.js

npx prettier --write --plugin=prettier-plugin-solidity 'contracts/**/*.sol' 'test/**/*.sol'