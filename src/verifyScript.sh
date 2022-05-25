#!/bin/sh
forge verify-contract --compiler-version "v0.6.12+commit.27d51765" \
  0x5a89e762dE3644B25dB99Be05D195b152E8e0683 src/UniswapTwapPriceOracleV2Ceiling.sol:UniswapTwapPriceOracleV2Ceiling $1
