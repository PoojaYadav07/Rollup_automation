#!/bin/bash

# Move to the correct working directory
#cd /var/lib/jenkins/pipeline_automation/Rollup_automation/Rollup || exit 1

# Source driver details
#source /var/lib/jenkins/pipeline_automation/Rollup_automation/Rollup

# Define configuration file paths
CONFIG_FILE="/Users/poojayadav/Downloads/pipeline_automation/Rollup_automation/Rollup/groupby_configs.json"
DEPENDENCY_FILE="/Users/poojayadav/Downloads/pipeline_automation/Rollup_automation/Rollup/dependencies.txt"

# Parameters passed from Jenkins
ORGANIZATION=$1
VIEW=$2
COLUMNS_JSON=$3
TYPES=$4

# Generate a unique projection ID
generate_projection_id() {
  local organization="$1"
  local view="$2"
  local type="$3"
  echo "${organization}_${view}_${type}_$(date +'%d%b%y')"
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
  local columns="$1"
  local formatted_columns

  if [[ "$columns" == *","* ]]; then
    IFS=',' read -ra COL_ARRAY <<< "$columns"
    #formatted_columns="["
    for col in "${COL_ARRAY[@]}"; do
      formatted_columns+="\"${col}\",\n"
    done
    formatted_columns=$(echo -e "$formatted_columns" | sed '$s/,$//')
  else
    formatted_columns="[\"$columns\"]"
  fi

  echo "$formatted_columns"
}

# Function to replace placeholders in JSON template
replace_placeholders() {
  local template="$1"
  local granularity="$2"
  local range="$3"
  local trigger="$4"
  local projection_id="$5"
  local dependency="$6"
  local formatted_columns="$7"

  # Replace placeholders
  template="${template//\$\{COLUMNS_JSON\}/$formatted_columns}"
  template="${template//\$\{GRANULARITY\}/$granularity}"
  template="${template//\$\{RANGE\}/$range}"
  template="${template//\$\{TRIGGER\}/$trigger}"
  template="${template//\$\{DEPENDENCIES\}/$dependency}"
  template="${template//\$\{PROJECTION_ID\}/$projection_id}"

  echo "$template"
}

# Function to generate JSON file
generate_json() {
  local json_content="$1"
  local type="$2"
  local output_file="Rollup_${ORGANIZATION}_$(date +'%Y%m%d%H%M%S').json"

  echo "$json_content" >> "$output_file"
  echo "Generated JSON file: $output_file"
}

# Function to validate organization and view
validate_organization_view() {
  local organization="$1"
  local view="$2"
  local config_file="$3"

  local result
  result=$(jq -r "
    if (type == \"object\" and has(\"$organization\")) and 
       (.\"$organization\" | type == \"object\" and has(\"$view\")) 
    then \"valid\" 
    else \"invalid\" 
    end
  " "$config_file")

  if [[ "$result" == "invalid" ]]; then
    echo "Error: Invalid organization or view combination: $organization - $view"
    exit 1
  fi
}

# Function to process types and generate JSON
process_types() {
  local organization="$1"
  local view="$2"
  local json_template="$3"
  local types="$4"
  local formatted_columns="$5"
  local last_projection_id=""

  IFS=',' read -ra TYPE_ARRAY <<< "$types"
  for type in "${TYPE_ARRAY[@]}"; do
    case $type in
      HR)
        granularity="hour"
        range="hour"
        trigger="immediate"
        dependency=$(fetch_dependency "$organization" "$view" "HR")
        ;;
      DR)
        granularity="hour"
        range="day"
        trigger="oncomplete"
        dependency=$(fetch_dependency "$organization" "$view" "DR")
        ;;
      DG)
        granularity="day"
        range="day"
        trigger="oncomplete"
        dependency="$last_projection_id" # DG depends on DR's projection ID
        ;;
      WG)
        granularity="week"
        range="week"
        trigger="oncomplete"
        dependency="$last_projection_id" # WG depends on DS's projection ID
        ;;
      *)
        echo "Unknown type: $type"
        continue
        ;;
    esac

    # Generate projection ID
    projection_id=$(generate_projection_id "$organization" "$view" "$type")

    # Replace placeholders in the JSON template
    json_content=$(replace_placeholders "$json_template" "$granularity" "$range" "$trigger" "$projection_id" "$dependency" "$formatted_columns")

    # Save the last projection ID for cascading dependencies
    last_projection_id="$projection_id"

    # Generate JSON file
    generate_json "$json_content" "$type"
  done
}

# Main script logic
validate_organization_view "$ORGANIZATION" "$VIEW" "$CONFIG_FILE"
JSON_TEMPLATE=$(jq -r ".\"$ORGANIZATION\".\"$VIEW\"" "$CONFIG_FILE")
FORMATTED_COLUMNS_JSON=$(format_columns_json "$COLUMNS_JSON")
process_types "$ORGANIZATION" "$VIEW" "$JSON_TEMPLATE" "$TYPES" "$FORMATTED_COLUMNS_JSON"
