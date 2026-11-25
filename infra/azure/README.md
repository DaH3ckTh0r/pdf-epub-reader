# Azure infrastructure

Bicep templates for the sync backend and the AI Foundry resources.

## What gets created

| Resource | Purpose |
|---|---|
| Storage account + `books` container | Original PDF/EPUB files |
| Cosmos DB (serverless, SQL API) `reader/sync` | Reading progress, notes, library index, partitioned by `userId` |
| Key Vault (RBAC) | Secrets and configuration |
| AI Foundry account (`AIServices`) | Model access for the "explain this" feature |
| Foundry project | Groups the app's AI resources |
| Model deployment | Chat model used by the reader |

## Deploy

```bash
az group create -n rg-lectorpdf-dev -l eastus2
az deployment group create -g rg-lectorpdf-dev -f main.bicep -p main.bicepparam
```

Before deploying, fill in `main.bicepparam`:
- `adminObjectId`: `az ad signed-in-user show --query id -o tsv`
- `modelVersion` and `modelName`: list what your region offers with `az cognitiveservices account list-models`.

## Manual steps (not in Bicep)

- **Entra ID app registration** for sign-in. Create it in the portal or with Microsoft Graph, then add the app's client ID to the app config.
- **Foundry access**: the account has `disableLocalAuth: true`, so the app should authenticate with Entra ID through a managed identity or `DefaultAzureCredential`, not an API key.
- **Free vs paid tier**: the template sets the SKU to `S0` and the model to `GlobalStandard`. Confirm in the Foundry pricing page which tier you're on before a production deployment.

## Notes

- Cosmos DB uses `disableLocalAuth: true`, so access is through Entra ID RBAC, not keys.
- Storage has public blob access disabled. Serve books through short-lived SAS links or through the API.
