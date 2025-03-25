set -euo pipefail

# clear the output files
> gate_counts.json

# Initialize JSON structure
echo "{" > gate_counts.json

aztec-wallet import-test-accounts
aztec-wallet deploy token_contract@Token --args Token TKN 18 accounts:test0 -f accounts:test0 -a token --init "constructor_with_minter"

process_output() {
    local operation=$1
    local profile_output=$2
    local execution_output=$3
    local is_last=${4:-"false"}

    # Start the operation object
    echo "  \"$operation\": {" >> gate_counts.json
    echo "    \"circuits\": {" >> gate_counts.json
    
    # Process each line with Gates
    local first_circuit=true
    echo "$profile_output" | grep "Gates:" | while read -r line; do
        # Extract circuit name and gate count
        circuit_name=$(echo "$line" | awk -F'Gates:' '{print $1}' | xargs)
        gates=$(echo "$line" | awk '{print $3}' | tr -d ',')
        
        # Add comma for all but first entry
        if [ "$first_circuit" = true ]; then
            first_circuit=false
        else
            echo "," >> gate_counts.json
        fi
        
        # Write circuit data
        echo -n "      \"$circuit_name\": $gates" >> gate_counts.json
    done
    
    # Get total gates
    total_gates=$(echo "$profile_output" | grep "Total gates:" | awk '{print $3}' | tr -d ',')

    # process the execution output (the gas values)
    local gas_values=$(extract_gas_values "$execution_output")

    # add the gas values to the json
    
    # Close circuits object and add total
    echo -e "\n    }," >> gate_counts.json
    echo -n "    \"gas_values\": $gas_values," >> gate_counts.json
    echo -n "    \"total_gates\": $total_gates" >> gate_counts.json
    
    # Close operation object
    if [ "$is_last" = "true" ]; then
        echo -e "\n  }" >> gate_counts.json
    else
        echo -e "\n  }," >> gate_counts.json
    fi
}

function extract_gas_values() {
    local output="$1"
    local -a values=($(echo "$output" | awk -F'[=,]' '/Estimated gas usage:/{print $2, $4, $6, $8}'))

    if [ ${#values[@]} -eq 4 ]; then
        echo "{
      \"da\": ${values[0]},
      \"l2\": ${values[1]},
      \"teardownDA\": ${values[2]},
      \"teardownL2\": ${values[3]}
    }"
        return 0
    else
        echo "Error: Could not extract gas values" >&2
        return 1
    fi
}

runAndProfile() {
    local operation=$1
    local args=$2
    local from=$3
    local is_last=${4:-"false"}
    local PROFILE_CMD="aztec-wallet profile -ca token $operation --args $args -f $from"
    local SEND_CMD="aztec-wallet send -ca token $operation --args $args -f $from"
    profile_output=$($PROFILE_CMD)
    gas_output=$($SEND_CMD)
    process_output "$operation" "$profile_output" "$gas_output" "$is_last"
}

ALICE=accounts:test0
BOB=accounts:test1
CARL=accounts:test2

CALLER=$ALICE
MINTER=$ALICE

NOTE_AMOUNT=1000

# Setup initial state
# aztec-wallet send mint_to_public -ca token --args $ALICE $NOTE_AMOUNT -f $CALLER

runAndProfile "mint_to_public" "$ALICE $NOTE_AMOUNT" "$MINTER"

## profile mints

runAndProfile "mint_to_private" "$ALICE $ALICE $NOTE_AMOUNT" "$MINTER"

# ## profile burns

runAndProfile "burn_private" "$ALICE 10 0" "$ALICE"

runAndProfile "burn_public" "$ALICE 10 0" "$ALICE"

## Profile transfers

runAndProfile "transfer_private_to_private" "$ALICE $BOB 10 0" "$ALICE"

runAndProfile "transfer_private_to_public" "$ALICE $BOB 10 0" "$ALICE"

runAndProfile "transfer_public_to_public" "$ALICE $BOB 10 0" "$ALICE"

runAndProfile "transfer_public_to_private" "$ALICE $BOB 10 0" "$ALICE"

## profile partial notes

# we simulate the prepare tx to get the commitment from the simulation result
COMMITMENT=$(aztec-wallet simulate -ca token "prepare_transfer_public_to_private" --args $ALICE $BOB -f $ALICE | \
    sed -n 's/.*commitment: \([0-9]*\)n.*/\1/p') # extract the commitment value from the output simulation
# convert to hex using `bc` because we're dealing with big numbers.
hex=$(echo "obase=16; $COMMITMENT" | bc)

runAndProfile "prepare_transfer_public_to_private" "$ALICE $BOB" "$ALICE"
# aztec-wallet send prepare_transfer_public_to_private -ca token --args $ALICE $BOB -f $ALICE

# Submit tx to prepare the commitment
# aztec-wallet send prepare_transfer_public_to_private -ca token --args $ALICE $BOB -f $ALICE

# Use proper string interpolation for the hex value while maintaining JSON structure
runAndProfile "finalize_transfer_public_to_private" "$ALICE 17 {\"commitment\":\"0x$hex\"}  0" "$ALICE" "true"


# aztec-wallet send finalize_transfer_public_to_private -ca token --args $ALICE 17 "{\"commitment\":\"0x$hex\"}" 0 -f $ALICE

## profile recursive note fetching

# Mints 5 notes to Alice, each note with 1000
# for i in {1..1}; do
#     aztec-wallet send mint_to_private -ca token --args $ALICE $ALICE $NOTE_AMOUNT -f $MINTER
# done

# Close the JSON
echo "}" >> gate_counts.json