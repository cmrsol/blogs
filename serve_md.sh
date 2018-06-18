#!/bin/bash

usage="${0} <markdown-file> [html-title]"
page=${1}

if [ ! -f "${page}" ]; then
	echo "${usage}"
	exit 2
fi

if [ -z "${2}" ]; then
    nohup grip ${page} 0.0.0.0:8080 > /dev/null 2>/dev/null &
else
    nohup grip --title="${2}" ${page} 0.0.0.0:8080 > /dev/null 2>/dev/null &
fi

sleep 2
jobs
