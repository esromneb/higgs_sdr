#!/bin/bash

set -e

for directory in \
    libs/burbulator \
    libs/datapath \
    libs/d-engine/rtl/reciprocal
do
    (
        cd "$directory"
        npm install
        npm run build
    )
done
