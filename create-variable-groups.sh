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

# Install jq and curl if missing
if ! command -v jq &> /dev/null; then
  echo "📦 Installing jq..."
  curl -L -o jq https://github.com/stedolan/jq/releases/latest/download/jq-linux64
  chmod +x jq
  export PATH=$PATH:.
fi

if ! command -v curl &> /dev/null; then
  echo "📦 Installing curl..."
  sudo apt-get update && sudo apt-get install -y curl
fi

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

  echo "🔍 Preparing variable group JSON structure..."

  RAW_VARS=$(echo "$item" | jq -e '.variables') || {
    echo "❌ ERROR: Missing or invalid 'variables' field in JSON."
    echo "Offending entry:"
    echo "$item"
    exit 1
  }

  VARS_JSON=$(echo "$RAW_VARS" | jq 'to_entries | map({key: .key, value: { value: .value, isSecret: false }}) | from_entries') || {
    echo "❌ ERROR: Failed to convert variables into required format"
    echo "$RAW_VARS"
    exit 1
  }

  BODY=$(jq -n \
    --arg name "$VG_NAME" \
    --argjson variables "$VARS_JSON" \
    '{
      type: "Vsts",
      name: $name,
      variables: $variables
    }') || {
      echo "❌ ERROR: Failed to construct final request body"
      exit 1
  }

  echo "✅ Constructed request body successfully."

  echo "$BODY" > payload.json
  echo "📤 JSON request payload saved to payload.json:"
  jq . payload.json || {
    echo "❌ Invalid JSON in payload.json"
    cat payload.json
    exit 1
  }

  URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"
  echo "🌐 Sending POST to: $URL"

  # Safe curl call with debug output
  set +e

  RESPONSE_FILE=$(mktemp 2>/dev/null)
  if [[ -z "$RESPONSE_FILE" ]]; then
    RESPONSE_FILE="response.json"
  fi

  HTTP_CODE=$(curl --http1.1 -s -w "%{http_code}" -o "$RESPONSE_FILE" -X POST \
    -H "$AUTH_HEADER" \
    -H "Content-Type: application/json" \
    -d @payload.json \
    "$URL")

  CURL_EXIT_CODE=$?

  set -e

  echo ""
  echo "🐞 Debug Info:"
  echo "curl exit code: $CURL_EXIT_CODE"
  echo "HTTP status: $HTTP_CODE"
  echo ""
  echo "📄 Full payload.json content:"
  cat payload.json
  echo ""
  echo "📨 API Response:"
  cat "$RESPONSE_FILE"
  echo ""

  if [[ "$HTTP_CODE" -ge 400 ]]; then
    echo ""
    echo "❌ ERROR: Failed to create variable group: $VG_NAME"
    echo "💡 HINT: Check if the PAT has permission: Variable Groups (Read & Manage)"
    echo "💡 HINT: Verify organization/project: $ORG / $PROJECT"
    echo "💡 HINT: Ensure variable group name is unique and doesn't already exist"
    exit 1
  else
    echo "✅ Successfully created variable group: $VG_NAME"
  fi

done
