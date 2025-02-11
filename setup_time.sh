#!/usr/bin/env bash

set -Eeuo pipefail

source ./vars.env

# Function to output SLOT_PER_EPOCH for mainnet or minimal
get_spec_preset_value() {
  case "$SPEC_PRESET" in
    mainnet)   echo 32 ;;
    minimal)   echo 8  ;;
    gnosis)    echo 16 ;;
    *)         echo "Unsupported preset: $SPEC_PRESET" >&2; exit 1 ;;
  esac
}

SLOT_PER_EPOCH=$(get_spec_preset_value $SPEC_PRESET)
echo "slot_per_epoch=$SLOT_PER_EPOCH"

genesis_file=$1

# Update future hardforks time in the EL genesis file based on the CL genesis time
GENESIS_TIME=$(lcli pretty-ssz --spec $SPEC_PRESET --testnet-dir $TESTNET_DIR BeaconState $TESTNET_DIR/genesis.ssz | jq | grep -o '"genesis_time": "[^"]*' | grep -o '[^"]*$')
echo $GENESIS_TIME

CAPELLA_TIME=$((GENESIS_TIME + (CAPELLA_FORK_EPOCH * $SLOT_PER_EPOCH * SECONDS_PER_SLOT)))
HELIUM_TIME=$((GENESIS_TIME + (HELIUM_FORK_EPOCH * $SLOT_PER_EPOCH * SECONDS_PER_SLOT)))
echo "HELIUM_TIME: " + $HELIUM_TIME
sed -i -e 's/"shanghaiTime".*$/"shanghaiTime": '"$CAPELLA_TIME"',/g' $genesis_file
sed -i -e 's/"heliumTime".*$/"heliumTime": '"$HELIUM_TIME"'/g' $genesis_file

# CANCUN_TIME=$((GENESIS_TIME + (DENEB_FORK_EPOCH * $SLOT_PER_EPOCH * SECONDS_PER_SLOT)))
# echo $CANCUN_TIME
# sed -i -e 's/"cancunTime".*$/"cancunTime": '"$CANCUN_TIME"',/g' $genesis_file

