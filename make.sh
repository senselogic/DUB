#!/bin/sh
set -x
dmd -m64 dub.d
rm *.o
