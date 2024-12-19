#!/bin/bash

# Move to the correct working directory
#cd /pipeline_automation/Rollup_automation/Rollup || exit 1

# Source driver details
#source /Users/poojayadav/Downloads/pipeline_automation/Rollup_automation/Rollup

# Define configuration file paths
CONFIG_FILE="/Users/poojayadav/Downloads/pipeline_automation/Rollup_automation/Rollup/groupby_configs.json"

# Parameters passed from Jenkins
ORGANIZATION=$1
VIEW=$2
COLUMNS_JSON=$3
TYPES=$4 # Multiple values separated by commas, e.g., "HR,DR,DS,WR"
DEPENDENCIES=$5

# Generate a unique projection ID
generate_projection_id() {
  local granularity=$1
  echo "${organization}_${view}_${type}_$(date +'%d%b%y')"
}

# Function to generate JSON
generate_json() {
  local json_content="$1"
  local type="$2"
  local json_file="Rollup_${ORGANIZATION}_$(date +'%Y%m%d%H%M%S').json"
  
  # Append the new JSON object
  echo "$json_content" >> "$json_file"
  
  # Close the array
  #echo "]" >> "$json_file"
  
  echo "Generated JSON has been appended to $json_file"
}

# Function to replace placeholders in JSON template
replace_placeholders() {
  local template="$1"
  local granularity="$2"
  local range="$3"
  local trigger="$4"
  local projection_id="$5"

 # Format COLUMNS_JSON as JSON array
local formatted_column_json=""
if [[ "$COLUMNS_JSON" == *","* ]]; then
  IFS=',' read -ra COLUMNS <<< "$COLUMNS_JSON"
  for col in "${COLUMNS[@]}"; do
    formatted_column_json+="\"${col}\"\n"
  done
  formatted_column_json=$(echo -e "$formatted_column_json" | sed '$s/,$//')
else
  formatted_column_json="[\"$COLUMNS_JSON\"]"
fi

  # Replace placeholders
  template="${template//\$\{COLUMNS_JSON\}/$formatted_column_json}"
  template="${template//\$\{GRANULARITY\}/$granularity}"
  template="${template//\$\{RANGE\}/$range}"
  template="${template//\$\{TRIGGER\}/$trigger}"
  template="${template//\$\{DEPENDENCIES\}/$DEPENDENCIES}"
  template="${template//\$\{PROJECTION_ID\}/$projection_id}"

  echo "$template"
}

# Validation function
validate_organization_view() {
  local ORGANIZATION="$1"
  local VIEW="$2"
  local CONFIG_FILE="$3"


  # Validate the organization and view
  local result
  result=$(jq -r "
    if (type == \"object\" and has(\"$ORGANIZATION\")) and 
       (.\"$ORGANIZATION\" | type == \"object\" and has(\"$VIEW\")) 
    then \"valid\" 
    else \"invalid\" 
    end
  " "$CONFIG_FILE")

  if [[ "$result" == "invalid" ]]; then
    echo "Error: Invalid organization or view combination: $ORGANIZATION - $VIEW"
    exit 1
  fi
}

# Validate organization and view
validate_organization_view "$ORGANIZATION" "$VIEW" "$CONFIG_FILE"

# Extract JSON template
JSON_TEMPLATE=$(jq -r ".\"$ORGANIZATION\".\"$VIEW\"" "$CONFIG_FILE")

# Iterate over each type and generate JSON
IFS=',' read -ra TYPE_ARRAY <<< "$TYPES"
for type in "${TYPE_ARRAY[@]}"; do
  case $type in
    HR)
      granularity="hour"
      range="hour"
      trigger="immediate"
      ;;
    DR)
      granularity="hour"
      range="day"
      trigger="oncomplete"
      ;;
    DS)
      granularity="day"
      range="day"
      trigger="oncomplete"
      ;;
    WR)
      granularity="week"
      range="week"
      trigger="oncomplete"
      ;;
    *)
      echo "Unknown type: $type"
      continue
      ;;
  esac

  projection_id=$(generate_projection_id "$granularity")
  json_content=$(replace_placeholders "$JSON_TEMPLATE" "$granularity" "$range" "$trigger" "$projection_id")
  generate_json "$json_content" "$type"
done
