#!/bin/sh
forge verify-contract --compiler-version "v0.6.12+commit.27d51765" \
  0x6Dc81dde0030AFfdd9f5EA90F742b2b1118fBbA2 src/InvFeed.sol:InvFeed $1
