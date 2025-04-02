# Filter function from token compilation output file, filter public and private, but no internal.
# also filter out "public_dispatch" and "sync_notes"
entrypoints=$(jq -r '
  .functions[]
  | select(.custom_attributes | length == 1 and (.[0] == "private" or .[0] == "public"))
  | select(.name != "public_dispatch" and .name != "sync_notes")
  | .name
' target/token_contract-Token.json)

# Check for corresponding test files
missing_tests=""
for entrypoint in $entrypoints; do
    if [ ! -f "src/token_contract/src/test/$entrypoint.nr" ]; then
        missing_tests="$missing_tests$entrypoint\n"
    fi
done

# fail if there are missing tests
if [ -n "$missing_tests" ]; then
    echo "Missing test files for:\n$missing_tests"
    exit 1
fi
