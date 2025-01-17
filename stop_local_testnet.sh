#!/usr/bin/env bash
# Stop all processes that were started with start_local_testnet.sh

set -Eeuo pipefail

source ./vars.env

PID_FILE=$TESTNET_DIR/PIDS
for entry in "$PID_FILE"/*
do
  ./kill_processes.sh $entry
done

rm -rf $PID_FILE
