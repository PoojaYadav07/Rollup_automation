#!/bin/bash

# Configuration file path
MONGO_CONF="/Users/poojayadav/Downloads/pipeline_automation/Rollup_automation/Rollup/mongo_config.json"


get_mongodb_credentials() {
    local organization="$1"
    local view="$2"

    # Extract database and credentials key from the configuration file
    local db_mapping=$(jq -r --arg org "$organization" --arg view "$view" \
    '.database_mapping[$org][$view] // empty' "$MONGO_CONF")

    
    if [[ "$db_mapping" == "null" ]]; then
        echo "Error: Organization or view not found in database mapping." >&2
        return 1
    fi

    local database=$(echo "$db_mapping" | jq -r '.database')
    local cred_key=$(echo "$db_mapping" | jq -r '.credentials')

    # Extract connection details from credentials
    local host=$(jq -r --arg key "$cred_key" '.credentials[$key].host' "$MONGO_CONF")
    local port=$(jq -r --arg key "$cred_key" '.credentials[$key].port' "$MONGO_CONF")
    local username=$(jq -r --arg key "$cred_key" '.credentials[$key].username' "$MONGO_CONF")
    local password=$(jq -r --arg key "$cred_key" '.credentials[$key].password' "$MONGO_CONF")

    if [[ -z "$database" || "$database" == "null" || -z "$host" || "$host" == "null" || \
          -z "$port" || "$port" == "null" || -z "$username" || "$username" == "null" || \
          -z "$password" || "$password" == "null" ]]; then
        echo "Error: Missing or invalid database or credential information." >&2
        return 1
    fi

    echo "$host:$port:$database:$username:$password"
}

fetch_metric_details() {
    local organization="$1"
    local view="$2"

    if [[ ! -f "$MONGO_CONF" ]]; then
        echo "Error: Configuration file not found at $MONGO_CONF" >&2
        return 1
    fi

    # Get MongoDB credentials
    local credentials
    credentials=$(get_mongodb_credentials "$organization" "$view")
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to retrieve MongoDB credentials." >&2
        return 1
    fi

    IFS=':' read -r host port database username password <<< "$credentials"

    # MongoDB query to fetch metric details
    local query='db.getCollection("Projections").findOne({type:"GROUPBY",indexingDisabled:false},{_id:0,agg:1})'

    echo "Connecting to MongoDB at $host:$port for database $database..." >&2

    # Execute the query using mongosh
    local result
    result=$(MONGOSH_SILENT=1 mongosh \
        --host "$host" \
        --port "$port" \
        --username "$username" \
        --password "$password" \
        --authenticationDatabase "admin" \
        "$database" \
        --quiet \
        --eval "$query" 2>&1)

    # Check for errors
    if [[ $? -ne 0 ]]; then
        echo "Error: MongoDB query failed:" >&2
        echo "$result" >&2
        return 1
    fi

    # Check if result is empty or null
    if [[ -z "$result" || "$result" == "null" ]]; then
        echo "Error: No data found in MongoDB query result." >&2
        return 1
    fi

    echo "Query Result:"
    echo "$result"
}

# Main execution
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <organization> <view>"
    exit 1
fi

ORGANIZATION="$1"
VIEW="$2"

fetch_metric_details "$ORGANIZATION" "$VIEW"
