#!/usr/bin/env bash
# Start all processes necessary to create a local testnet

set -Eeuo pipefail

source ./vars.env

# Set a higher ulimit in case we want to import 1000s of validators.
ulimit -n 65536

# VC_COUNT is defaulted in vars.env
DEBUG_LEVEL=${DEBUG_LEVEL:-info}
BUILDER_PROPOSALS=

# Get options
while getopts "v:d:ph" flag; do
  case "${flag}" in
    v) VC_COUNT=${OPTARG};;
    d) DEBUG_LEVEL=${OPTARG};;
    p) BUILDER_PROPOSALS="-p";;
    h)
        validators=$(( $VALIDATOR_COUNT / $BN_COUNT ))
        echo "Start local testnet, defaults: 1 eth1 node, $BN_COUNT beacon nodes,"
        echo "and $VC_COUNT validator clients with each vc having $validators validators."
        echo
        echo "usage: $0 <Options>"
        echo
        echo "Options:"
        echo "   -v: VC_COUNT    default: $VC_COUNT"
        echo "   -d: DEBUG_LEVEL default: info"
        echo "   -p:             enable builder proposals"
        echo "   -h:             this help"
        exit
        ;;
  esac
done

genesis_file="genesis.json"

# Init some constants
PID_FILE=$TESTNET_DIR/PIDS
LOG_DIR=$TESTNET_DIR

# Stop local testnet and remove $PID_FILE
./stop_local_testnet.sh

# Clean $DATADIR and create empty log files so the
# user can "tail -f" right after starting this script
# even before its done.
./clean.sh
mkdir -p $LOG_DIR
mkdir -p $PID_FILE
for (( bn=1; bn<=$BN_COUNT; bn++ )); do
    touch $LOG_DIR/beacon_node_$bn.log
done
for (( el=1; el<=$BN_COUNT; el++ )); do
    touch $LOG_DIR/geth_$el.log
done
for (( vc=1; vc<=$VC_COUNT; vc++ )); do
    touch $LOG_DIR/validator_node_$vc.log
done

# Sleep with a message
sleeping() {
   echo sleeping $1
   sleep $1
}

# Execute the command with logs saved to a file.
#
# First parameter is log file name
# Second parameter is executable name
# Remaining parameters are passed to executable
execute_command() {
    LOG_NAME=$2
    EX_NAME=$3
    shift
    shift
    shift
    CMD="$EX_NAME $@ >> $LOG_DIR/$LOG_NAME 2>&1"
    echo "executing: $CMD"
    echo "$CMD" > "$LOG_DIR/$LOG_NAME"
    eval "$CMD &"
}

# Execute the command with logs saved to a file
# and is PID is saved to $PID_FILE.
#
# First parameter is log file name
# Second parameter is executable name
# Remaining parameters are passed to executable
execute_command_add_PID() {
    execute_command $@
    echo "$!" >> "$PID_FILE/$1"
}


# Setup data
echo "executing: ./setup.sh >> $LOG_DIR/setup.log"
./setup.sh >> $LOG_DIR/setup.log 2>&1

# Call setup_time.sh to update future hardforks time in the EL genesis file based on the CL genesis time
./setup_time.sh genesis.json

# Delay to let boot_enr.yaml to be created
execute_command_add_PID bootnode.pid bootnode.log ./bootnode.sh
sleeping 3

execute_command_add_PID el_bootnode.pid el_bootnode.log ./el_bootnode.sh
sleeping 3

# Start beacon nodes
BN_udp_tcp_base=9000
BN_http_port_base=8000

EL_base_network=7000
EL_base_http=6000
EL_base_auth_http=5000

(( $VC_COUNT < $BN_COUNT )) && SAS=-s || SAS=

for (( el=0; el<=1; el++ )); do
    execute_command_add_PID geth_$el.pid geth_$el.log ./geth.sh $DATADIR/geth_datadir$el $((EL_base_network + $el)) $((EL_base_http + $el)) $((EL_base_auth_http + $el)) $genesis_file
done

sleeping 10

for (( bn=1; bn<=$BN_COUNT; bn++ )); do
    el=$((bn % 2))
    secret=$DATADIR/geth_datadir$el/canxium/jwtsecret
    execute_command_add_PID beacon_node_$bn.pid beacon_node_$bn.log ./beacon_node.sh $SAS -d $DEBUG_LEVEL $DATADIR/node_$bn $((BN_udp_tcp_base + $bn)) $((BN_udp_tcp_base + $bn + 100)) $((BN_http_port_base + $bn)) http://localhost:$((EL_base_auth_http + $el)) $secret
done

# Start requested number of validator clients
for (( vc=1; vc<=$BN_COUNT; vc++ )); do
    execute_command_add_PID validator_node_$vc.pid validator_node_$vc.log ./validator_client.sh $BUILDER_PROPOSALS -d $DEBUG_LEVEL $DATADIR/node_$vc http://localhost:$((BN_http_port_base + $vc))
done

echo "Started!"
