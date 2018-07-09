#!/usr/bin/env bash
#
# Package charts and rebuild our index
#
# This must be done for every chart change - fix up versions, run
# this script, and commit.
#
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
(
    # Run this directory
    cd ${MY_DIR}

    for dir in ../stable/*
    do
        helm package ${dir}
    done

    helm repo index ./ --url https://stevetarver.github.io/charts
)