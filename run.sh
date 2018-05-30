#!/bin/bash
# Bash script to run the scripts in this repository
# Before you run anything, set the REPO_PATH variable to point
# towards the directory this script is in, eg. using:
export REPO_PATH=$PWD

julia jl_scripts/base_case.jl
# julia jl_scripts/carbon.jl
# julia jl_scripts/storage_sens.jl
