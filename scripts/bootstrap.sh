#!/usr/bin/env bash
set -euo pipefail
: "${GH_REPO:?Set GH_REPO=owner/repo}"
LOCATION="${LOCATION:-eastasia}"
STATE_RG="${STATE_RG:-tfstate-rg}"
STATE_SA="${STATE_SA:-tfstate$RANDOM$RANDOM}"
STATE_CONTAINER="${STATE_CONTAINER:-tfstate}"
APP_NAME="${APP_NAME:-github-tomato-aks}"

SUB_ID=$(az account show --query id -o tsv)

az group create -n "$STATE_RG" -l "$LOCATION" -o none
az storage account create -n "$STATE_SA" -g "$STATE_RG" -l "$LOCATION" \
  --sku Standard_LRS --min-tls-version TLS1_2 --allow-blob-public-access false -o none
az storage container create -n "$STATE_CONTAINER" --account-name "$STATE_SA" --auth-mode login -o none

APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
az ad sp create --id "$APP_ID" -o none

for entry in "main-branch|ref:refs/heads/main" "pull-request|pull_request"; do
  name="${entry%%|*}"; subj="${entry##*|}"
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"$name\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${GH_REPO}:${subj}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" -o none
done

SCOPE="/subscriptions/$SUB_ID"
az role assignment create --assignee "$APP_ID" --role "Contributor" --scope "$SCOPE" -o none
az role assignment create --assignee "$APP_ID" --role "User Access Administrator" --scope "$SCOPE" -o none
SA_ID=$(az storage account show -n "$STATE_SA" -g "$STATE_RG" --query id -o tsv)
az role assignment create --assignee "$APP_ID" --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none
echo "Bootstrap done. State storage account: $STATE_SA"
