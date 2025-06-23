#!/bin/bash

set -e

INPUT_FILE="variable-groups.json"
PAT="$1"

if [[ -z "$PAT" ]]; then
  echo "❌ ERROR: Missing Personal Access Token (PAT)."
  echo "Usage: ./create-variable-groups.sh <AZURE_DEVOPS_PAT>"
  exit 1
fi

# Properly encode PAT for Authorization header
ENCODED_PAT=$(printf ":%s" "$PAT" | base64 | tr -d '\n')
AUTH_HEADER="Authorization: Basic $ENCODED_PAT"

# Install jq if missing
if ! command -v jq &> /dev/null; then
  echo "📦 Installing jq..."
  curl -L -o jq https://github.com/stedolan/jq/releases/latest/download/jq-linux64
  chmod +x jq
  export PATH=$PATH:.
fi

# Validate input file
if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ ERROR: Cannot find $INPUT_FILE in $(pwd)"
  exit 1
else
  echo "✅ Found $INPUT_FILE. Previewing content:"
  cat "$INPUT_FILE"
fi

# Loop through JSON
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

  echo "🌐 Fetching project ID..."
  PROJECT_API_URL="https://dev.azure.com/$ORG/_apis/projects/$PROJECT?api-version=7.1-preview.1"
  PROJECT_ID=$(curl --http1.1 -s -H "$AUTH_HEADER" "$PROJECT_API_URL" | jq -r '.id')

  if [[ "$PROJECT_ID" == "null" || -z "$PROJECT_ID" ]]; then
    echo "❌ ERROR: Failed to fetch project ID for $PROJECT"
    exit 1
  fi
  echo "✅ Found project ID: $PROJECT_ID"

  # Prepare variable JSON
  RAW_VARS=$(echo "$item" | jq -e '.variables') || {
    echo "❌ ERROR: Missing or invalid 'variables' field in JSON."
    echo "Offending entry:"
    echo "$item"
    exit 1
  }

  VARS_JSON=$(echo "$RAW_VARS" | jq 'to_entries | map({key: .key, value: { value: .value, isSecret: false }}) | from_entries')

  BODY=$(jq -n \
    --arg name "$VG_NAME" \
    --argjson variables "$VARS_JSON" \
    --arg projectId "$PROJECT_ID" \
    --arg projectName "$PROJECT" \
    '{
      type: "Vsts",
      name: $name,
      variables: $variables,
      variableGroupProjectReferences: [
        {
          projectReference: {
            id: $projectId,
            name: $projectName
          },
          name: $name
        }
      ]
    }')

  echo "$BODY" > payload.json
  echo "📤 JSON request payload saved to payload.json:"
  jq . payload.json

  URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"
  echo "🌐 Sending POST to: $URL"

  set +e
  RESPONSE_FILE=$(mktemp 2>/dev/null || echo "response.json")

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
  echo "📨 API Response:"
  cat "$RESPONSE_FILE"

  if [[ "$HTTP_CODE" -ge 400 || "$HTTP_CODE" -eq 000 ]]; then
    echo "❌ ERROR: Failed to create variable group: $VG_NAME"
    exit 1
  else
    echo "✅ Successfully created variable group: $VG_NAME"
  fi

done
