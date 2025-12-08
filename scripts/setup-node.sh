#!/bin/bash

set -e

for directory in \
    libs/burbulator \
    libs/datapath \
    libs/d-engine/rtl/reciprocal \
    libs/q-engine/piston \
    libs/q-engine/xbaseband_ops \
    libs/riscv-baseband/permutator
do
    (
        cd "$directory"
        npm install
        npm run build
    )
done
