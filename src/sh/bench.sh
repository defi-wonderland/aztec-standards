set -euo pipefail

# clear the output files
> gate_counts.json

# Initialize JSON structure
echo "{" > gate_counts.json

aztec-wallet import-test-accounts
aztec-wallet deploy token_contract@Token --args Token TKN 18 accounts:test0 -f accounts:test0 -a token --init "constructor_with_minter"

process_profile_output() {
    local operation=$1
    local output=$2
    local is_last=${3:-"false"}

    # Start the operation object
    echo "  \"$operation\": {" >> gate_counts.json
    echo "    \"circuits\": {" >> gate_counts.json
    
    # Process each line with Gates
    local first_circuit=true
    echo "$output" | grep "Gates:" | while read -r line; do
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
    total_gates=$(echo "$output" | grep "Total gates:" | awk '{print $3}' | tr -d ',')
    
    # Close circuits object and add total
    echo -e "\n    }," >> gate_counts.json
    echo -n "    \"total_gates\": $total_gates" >> gate_counts.json
    
    # Close operation object
    if [ "$is_last" = "true" ]; then
        echo -e "\n  }" >> gate_counts.json
    else
        echo -e "\n  }," >> gate_counts.json
    fi
}

ALICE=accounts:test0
BOB=accounts:test1
CARL=accounts:test2

CALLER=$ALICE
MINTER=$ALICE

NOTE_AMOUNT=1000

# Setup initial state
aztec-wallet send mint_to_public -ca token --args $ALICE $NOTE_AMOUNT -f $CALLER
# Mints 5 notes to Alice, each note with 1000
for i in {1..5}; do
    aztec-wallet send mint_to_private -ca token --args $ALICE $ALICE $NOTE_AMOUNT -f $MINTER
done

## profile mints

process_profile_output "mint_to_private" \
    "$(aztec-wallet profile mint_to_private -ca token --args $ALICE $ALICE $NOTE_AMOUNT -f $MINTER)"

# process_profile_output "mint_to_public" \
#     "$(aztec-wallet profile mint_to_public -ca token --args $ALICE $NOTE_AMOUNT -f $MINTER)"

# ## profile burns

process_profile_output "burn_private" \
    "$(aztec-wallet profile burn_private -ca token --args $ALICE 10 0 -f $ALICE)"

# process_profile_output "burn_public" \
#     "$(aztec-wallet profile burn_public -ca token --args $ALICE 10 0 -f $ALICE)"

## Profile transfers

process_profile_output "transfer_private_to_private" \
    "$(aztec-wallet profile transfer_private_to_private -ca token --args $ALICE $BOB 10 0 -f $ALICE)"

process_profile_output "transfer_private_to_public" \
    "$(aztec-wallet profile transfer_private_to_public -ca token --args $ALICE $BOB 10 0 -f $ALICE)"

# process_profile_output "transfer_public_to_public" \
#     "$(aztec-wallet profile transfer_public_to_public -ca token --args $ALICE $BOB 10 0 -f $ALICE)"

process_profile_output "transfer_public_to_private" \
    "$(aztec-wallet profile transfer_public_to_private -ca token --args $ALICE $BOB 10 0 -f $ALICE)" \

## profile partial notes

COMMITMENT=$(aztec-wallet simulate -ca token "prepare_transfer_public_to_private" --args $ALICE $BOB -f $ALICE | \
    sed -n 's/.*commitment: \([0-9]*\)n.*/\1/p') # extract the commitment value from the output simulation

# convert to hex using bc because we're dealing with big numbers.
hex=$(echo "obase=16; $COMMITMENT" | bc)

process_profile_output "prepare_transfer_public_to_private" \
    "$(aztec-wallet profile prepare_transfer_public_to_private -ca token --args $ALICE $BOB -f $ALICE)" \
    "true"
# Submit tx to prepare the commitment
# aztec-wallet send prepare_transfer_public_to_private -ca token --args $ALICE $BOB -f $ALICE

# process_profile_output "finalize_transfer_public_to_private" \
#     "$(aztec-wallet profile finalize_transfer_public_to_private -ca token --args $ALICE 17 "{\"commitment\":\"0x$hex\"}" 0 -f $ALICE)" \
#     "true" # flag to mark this is the last operation, so we can close the json object

# aztec-wallet send finalize_transfer_public_to_private -ca token --args $ALICE 17 "{\"commitment\":\"0x$hex\"}" 0 -f $ALICE


## profile recursive note fetching

# Close the JSON
echo "}" >> gate_counts.json