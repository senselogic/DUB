#!/bin/sh
set -x
rm -rf REPOSITORY_FOLDER/
../dub --backup DATA_FOLDER_1/ REPOSITORY_FOLDER/ --verbose
../dub --backup DATA_FOLDER_2/ REPOSITORY_FOLDER/ --verbose
../dub --backup DATA_FOLDER_3/ REPOSITORY_FOLDER/ --verbose

