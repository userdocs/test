#!/bin/bash

if [[ -n "${GITHUB_REPOSITORY}" ]]; then echo "#################### yes"; fi

echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ $GITHUB_REPOSITORY"

echo "@@@@@@@@@@@@@@@@@@@@@ $(env &> /dev/null && echo $GITHUB_REPOSITORY)"
