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

# Start beacon nodes
BN_udp_tcp_base=9000
BN_http_port_base=8000

EL_base_network=7000
EL_base_http=6000
EL_base_auth_http=5000

(( $VC_COUNT < $BN_COUNT )) && SAS=-s || SAS=

if [ $1 = 'geth' ]; then
    for (( el=0; el<=1; el++ )); do
        ./kill_processes.sh "$PID_FILE/geth_$el.pid"
        rm -rf "$PID_FILE/geth_$el.pid"
        sleep 3
        execute_command_add_PID geth_$el.pid geth_$el.log ./geth.sh $DATADIR/geth_datadir$el $((EL_base_network + $el)) $((EL_base_http + $el)) $((EL_base_auth_http + $el)) $genesis_file
        sleep 3
    done
fi

if [ $1 = 'beacon' ]; then
    for (( bn=1; bn<=$BN_COUNT; bn++ )); do
        el=$((bn % 2))
        secret=$DATADIR/geth_datadir$el/canxium/jwtsecret
        
        ./kill_processes.sh "$PID_FILE/beacon_node_$bn.pid"
        rm -rf "$PID_FILE/beacon_node_$bn.pid"
        sleep 3
        execute_command_add_PID beacon_node_$bn.pid beacon_node_$bn.log ./beacon_node.sh $SAS -d $DEBUG_LEVEL $DATADIR/node_$bn $((BN_udp_tcp_base + $bn)) $((BN_udp_tcp_base + $bn + 100)) $((BN_http_port_base + $bn)) http://localhost:$((EL_base_auth_http + $el)) $secret
        sleep 3
    done
fi

# # Start requested number of validator clients
if [ $1 = 'vc' ]; then
    for (( vc=1; vc<=$BN_COUNT; vc++ )); do
        ./kill_processes.sh "$PID_FILE/validator_node_$vc.pid"
        rm -rf "$PID_FILE/validator_node_$vc.pid"
        sleep 3
        execute_command_add_PID validator_node_$vc.pid validator_node_$vc.log ./validator_client.sh $BUILDER_PROPOSALS -d $DEBUG_LEVEL $DATADIR/node_$vc http://localhost:$((BN_http_port_base + $vc))
        sleep 3
    done
fi

echo "Restarted!"
