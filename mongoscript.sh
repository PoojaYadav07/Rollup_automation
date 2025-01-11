#!/bin/bash

# Move to the correct working directory
#cd /var/lib/jenkins/pipeline_automation/Rollup_automation/Rollup || exit 1

# Source driver details
#source /var/lib/jenkins/pipeline_automation/Rollup_automation/Rollup
#source /Users/poojayadav/Downloads/pipeline_automation/Rollup_automation/Rollup/mongo_operations.sh

# Define configuration file paths
CONFIG_FILE="/Users/poojayadav/Downloads/pipeline_automation/Rollup_automation/Rollup/groupby_configs.json"
DEPENDENCY_FILE="/Users/poojayadav/Downloads/pipeline_automation/Rollup_automation/Rollup/dependencies.txt"
FETCH_METRIC_SCRIPT="/Users/poojayadav/Downloads/pipeline_automation/Rollup_automation/Rollup/mongo_operations.sh"

for file in "$CONFIG_FILE" "$DEPENDENCY_FILE" "$FETCH_METRIC_SCRIPT"; do
    if [[ ! -f "$file" ]]; then
        echo "Error: Required file not found: $file"
        exit 1
    fi
done

# Parameters passed from Jenkins
ORGANIZATION=$1
VIEW=$2
COLUMNS_JSON=$3
TYPES=$4
DEPENDENCY_OVERRIDE=$5  # Optional parameter

# Check required parameters
if [[ -z "$ORGANIZATION" || -z "$VIEW" || -z "$COLUMNS_JSON" || -z "$TYPES" ]]; then
    echo "Usage: $0 <organization> <view> <columns_json> <types> [dependency_override]"
    exit 1
fi

# Generate a unique projection ID
generate_projection_id() {
  local organization="$1"
  local view="$2"
  local type="$3"
  echo "${organization}_${view}_${type}_$(date +'%d%b%y_%H%M')"
}

# Function to fetch static dependency
fetch_dependency() {
  local organization="$1"
  local view="$2"
  local type="$3"
  local key="${organization},${view},${type}"
  local dependency

  dependency=$(grep "^$key=" "$DEPENDENCY_FILE" | cut -d'=' -f2)
  if [[ -z "$dependency" ]]; then
    echo "Error: No dependency found for $key in $DEPENDENCY_FILE"
    exit 1
  fi
  echo "$dependency"
}

# Function to format COLUMNS_JSON as a JSON array
format_columns_json() {
  local columns=$1
  columns=${columns#\"}  
  columns=${columns%\"}
  local formatted_columns=$(echo "$columns" | sed 's/,/","/g')
  echo "$formatted_columns"
}

# Make FETCH_METRIC_SCRIPT executable
chmod +x "$FETCH_METRIC_SCRIPT"

# Execute the MongoDB operations script to fetch metric details
echo "Fetching metric details for $ORGANIZATION and $VIEW..."
metric_details=$("$FETCH_METRIC_SCRIPT" "$ORGANIZATION" "$VIEW")
if [[ $? -ne 0 || -z "$metric_details" ]]; then
    echo "Error: Failed to fetch Metric Details for $ORGANIZATION and $VIEW"
    exit 1
fi

# Print fetched metric details for debugging
echo "Successfully fetched metric details"

# Escape any special characters in metric_details for JSON
metric_details=$(echo "$metric_details" | sed 's/"/\\"/g')

# Function to replace placeholders in JSON template
replace_placeholders() {
  local template="$1"
  local granularity="$2"
  local range="$3"
  local trigger="$4"
  local projection_id="$5"
  local dependency="$6"
  local formatted_columns="$7"
  local metric_details="$8"

  # Replace placeholders
  template="${template//\$\{COLUMNS_JSON\}/$formatted_columns}"
  template="${template//\$\{GRANULARITY\}/$granularity}"
  template="${template//\$\{RANGE\}/$range}"
  template="${template//\$\{TRIGGER\}/$trigger}"
  template="${template//\$\{DEPENDENCIES\}/$dependency}"
  template="${template//\$\{PROJECTION_ID\}/$projection_id}"
  template="${template//\$\{Metric_Details\}/$metric_details}"

  echo "$template"
}

# Function to generate JSON file
generate_json() {
  local json_content="$1"
  local type="$2"

  echo "$json_content"
}

# Function to process types and generate JSON
process_types() {
  local organization="$1"
  local view="$2"
  local json_template="$3"
  local types="$4"
  local formatted_columns="$5"
  local dependency_override="$6"
  local last_projection_id=""

  IFS=',' read -ra TYPE_ARRAY <<< "$types"
  for type in "${TYPE_ARRAY[@]}"; do
    case $type in
      HR)
        granularity="hour"
        range="hour"
        trigger="immediate"
        dependency=${dependency_override:-$(fetch_dependency "$organization" "$view" "HR")}
        ;;
      DR)
        granularity="hour"
        range="day"
        trigger="oncomplete"
        dependency=${dependency_override:-$(fetch_dependency "$organization" "$view" "DR")}
        ;;
      DG)
        granularity="day"
        range="day"
        trigger="oncomplete"
        dependency=${dependency_override:-$last_projection_id} # DG depends on DR's projection ID
        ;;
      WG)
        granularity="week"
        range="week"
        trigger="oncomplete"
        dependency=${dependency_override:-$last_projection_id} # WG depends on DS's projection ID
        ;;
      *)
        echo "Unknown type: $type"
        continue
        ;;
    esac

    # Generate projection ID
    projection_id=$(generate_projection_id "$organization" "$view" "$type")

    # Replace placeholders in the JSON template
    json_content=$(replace_placeholders "$json_template" "$granularity" "$range" "$trigger" "$projection_id" "$dependency" "$formatted_columns" "$metric_details")

    # Save the last projection ID for cascading dependencies
    last_projection_id="$projection_id"

    # Generate JSON file
    generate_json "$json_content" "$type"
  done
}

# Main script logic
JSON_TEMPLATE=$(jq -r ".\"$ORGANIZATION\".\"$VIEW\"" "$CONFIG_FILE")
FORMATTED_COLUMNS_JSON=$(format_columns_json "$COLUMNS_JSON")
process_types "$ORGANIZATION" "$VIEW" "$JSON_TEMPLATE" "$TYPES" "$FORMATTED_COLUMNS_JSON" "$DEPENDENCY_OVERRIDE"