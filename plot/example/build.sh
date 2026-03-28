#!/bin/bash
set -x
set -e

odin build . -out:prog.bin -debug -show-timings
# odin build . -out:prog.bin -o:speed

# ./prog.bin
