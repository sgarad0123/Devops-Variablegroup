#!/bin/bash

set -e

INPUT_FILE="variable-groups.json"
PAT="$1"

if [[ -z "$PAT" ]]; then
  echo "❌ ERROR: Missing Personal Access Token (PAT)."
  echo "Usage: ./create-variable-groups.sh <AZURE_DEVOPS_PAT>"
  exit 1
fi

# Prepare auth header
AUTH_HEADER="Authorization: Basic $(echo -n ":$PAT" | base64)"

# Validate input file exists
if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ ERROR: Cannot find $INPUT_FILE in $(pwd)"
  exit 1
else
  echo "✅ Found $INPUT_FILE. Previewing content:"
  cat "$INPUT_FILE"
fi

# Loop through each item in JSON array
jq -c '.[]' "$INPUT_FILE" | while read -r item; do
  ORG=$(echo "$item" | jq -r '.org')
  PROJECT=$(echo "$item" | jq -r '.project')
  ENV=$(echo "$item" | jq -r '.env')
  TRACK=$(echo "$item" | jq -r '.track')
  TRACKNAME=$(echo "$item" | jq -r '.trackName')

  if [[ "$TRACKNAME" == "null" || -z "$TRACKNAME" ]]; then
    echo "❌ ERROR: Missing 'trackName' in input JSON for one of the entries."
    exit 1
  fi

  VG_NAME="${ENV}-${TRACK}-${TRACKNAME}-vg"

  echo "🔧 Creating Variable Group: $VG_NAME under $ORG/$PROJECT"

  # Construct the variable JSON
  VARS_JSON=$(echo "$item" | jq '.variables' | jq 'to_entries | map({key: .key, value: { value: .value, isSecret: false }}) | from_entries')

  BODY=$(jq -n \
    --arg name "$VG_NAME" \
    --argjson variables "$VARS_JSON" \
    '{
      type: "Vsts",
      name: $name,
      variables: $variables
    }'
  )

  # API endpoint
  URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"

  echo "🌐 Calling API: $URL"
  echo "📤 Request Payload:"
  echo "$BODY" | jq .

  # Call API and capture output
  HTTP_CODE=$(curl -s -w "%{http_code}" -o response.json -X POST \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d "$BODY" \
    "$URL")

  echo "🔁 HTTP Status Code: $HTTP_CODE"
  echo "📨 API Response:"
  cat response.json
  echo ""

  # Exit if failed
  if [[ "$HTTP_CODE" -ge 400 ]]; then
    echo "❌ Failed to create variable group: $VG_NAME"
    exit 1
  else
    echo "✅ Successfully created variable group: $VG_NAME"
  fi
done
