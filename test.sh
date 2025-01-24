#!/bin/bash

if [[ -n "${GITHUB_REPOSITORY}" ]]; then echo "#################### yes"; fi

echo "@@@@@@@@@@@@@@@@@@@@@ $(env &> /dev/null && echo $HOGITHUB_REPOSITORYSTNAME)"
