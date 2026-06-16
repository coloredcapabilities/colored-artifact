#!/bin/bash

# Get the directory where this script is located (artifact root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHES_DIR="$SCRIPT_DIR/patches"

CHERI_ROOT=${CHERI_ROOT:-$HOME/cheri}
cd $CHERI_ROOT

git clone https://github.com/coloredcapabilities/juliet-test-suite.git

cd juliet-test-suite

./juliet.py 415 --generate
./juliet.py 416 --generate
./juliet.py 415 --make
./juliet.py 416 --make
