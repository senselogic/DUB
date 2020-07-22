#!/bin/sh
set -x
rm -rf DATA_FOLDER/
rm -rf REPOSITORY_FOLDER/
../dub --backup DATA_FOLDER_1/ REPOSITORY_FOLDER/ --verbose
../dub --restore DATA_FOLDER/ REPOSITORY_FOLDER/ --verbose
../dub --backup DATA_FOLDER_2/ REPOSITORY_FOLDER/
../dub --restore DATA_FOLDER/ REPOSITORY_FOLDER/
../dub --backup DATA_FOLDER_3/ REPOSITORY_FOLDER/
../dub --restore DATA_FOLDER/ REPOSITORY_FOLDER/
../dub --list REPOSITORY_FOLDER/
../dub --list REPOSITORY_FOLDER/ "*"
../dub --list REPOSITORY_FOLDER/ "*" "*"
../dub --find REPOSITORY_FOLDER/
