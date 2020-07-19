#!/bin/sh
set -x
dmd -debug -g -gf -gs -m64 dub.d
rm *.o
