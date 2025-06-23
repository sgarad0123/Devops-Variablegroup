#!/bin/bash

set -e

INPUT_FILE="variable-groups.json"
PAT="$1"

if [[ -z "$PAT" ]]; then
  echo "❌ ERROR: Missing Personal Access Token (PAT)."
  echo "Usage: ./create-variable-groups.sh <AZURE_DEVOPS_PAT>"
  exit 1
fi

AUTH_HEADER="Authorization: Basic $(echo -n ":$PAT" | base64)"

# Validate input file
if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ ERROR: Cannot find $INPUT_FILE in $(pwd)"
  exit 1
else
  echo "✅ Found $INPUT_FILE. Previewing content:"
  cat "$INPUT_FILE"
fi

# Loop through JSON array
jq -c '.[]' "$INPUT_FILE" | while read -r item; do
  ORG=$(echo "$item" | jq -r '.org')
  PROJECT=$(echo "$item" | jq -r '.project')
  ENV=$(echo "$item" | jq -r '.env')
  TRACK=$(echo "$item" | jq -r '.track')
  TRACKNAME=$(echo "$item" | jq -r '.trackName')

  if [[ "$TRACKNAME" == "null" || -z "$TRACKNAME" ]]; then
    echo "❌ ERROR: Missing 'trackName' in input JSON."
    exit 1
  fi

  VG_NAME="${ENV}-${TRACK}-${TRACKNAME}-vg"
  echo "🔧 Creating Variable Group: $VG_NAME under $ORG/$PROJECT"

  # Construct variable group JSON
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

  # Save to file for debugging
  echo "$BODY" > payload.json

  echo "📤 JSON request payload saved to payload.json:"
  jq . payload.json || {
    echo "❌ Invalid JSON in payload.json"
    cat payload.json
    exit 1
  }

  # API call
  URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"
  echo "🌐 Sending POST to: $URL"

  HTTP_CODE=$(curl -s -w "%{http_code}" -o response.json -X POST \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d @payload.json \
    "$URL")

  echo ""
  echo "🔁 HTTP Status Code: $HTTP_CODE"
  echo ""
  echo "📄 Full payload.json content:"
  cat payload.json
  echo ""
  echo "📨 API Response:"
  cat response.json
  echo ""

  if [[ "$HTTP_CODE" -ge 400 ]]; then
    echo ""
    echo "❌ ERROR: Failed to create variable group: $VG_NAME"
    echo "💡 HINT: Check if the PAT has permission: Variable Groups (Read & Manage)"
    echo "💡 HINT: Verify organization/project: $ORG / $PROJECT"
    echo "💡 HINT: Ensure variable group name is unique"
    exit 1
  else
    echo "✅ Successfully created variable group: $VG_NAME"
  fi

done
