#!/bin/bash
set -e

INPUT_FILE="variable-groups.json"
PAT="$1"

if [[ -z "$PAT" ]]; then
  echo "Usage: ./create-variable-groups.sh <AZURE_DEVOPS_PAT>"
  exit 1
fi

AUTH_HEADER="Authorization: Basic $(echo -n ":$PAT" | base64)"

jq -c '.[]' "$INPUT_FILE" | while read -r item; do
  ORG=$(echo "$item" | jq -r '.org')
  PROJECT=$(echo "$item" | jq -r '.project')
  ENV=$(echo "$item" | jq -r '.env')
  TRACK=$(echo "$item" | jq -r '.track')
  VG_NAME="${ENV}-${TRACK}-svg"

  echo "Creating Variable Group: $VG_NAME under $ORG/$PROJECT"

  VARS_JSON=$(echo "$item" | jq '.variables' | jq 'to_entries | map({key: .key, value: { value: .value, isSecret: false }}) | from_entries')

  BODY=$(jq -n \
    --arg name "$VG_NAME" \
    --argjson variables "$VARS_JSON" \
    '{
      type: "Vsts",
      name: $name,
      variables: $variables
    }')

  URL="https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups?api-version=7.1-preview.2"

  RESPONSE=$(curl -s -X POST -H "$AUTH_HEADER" -H "Content-Type: application/json" -d "$BODY" "$URL")
  echo "Created: $(echo "$RESPONSE" | jq -r '.name')"
done
