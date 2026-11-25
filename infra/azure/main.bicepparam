using 'main.bicep'

param prefix = 'lectorpdf'
param env = 'dev'

// Replace with your Entra ID object ID:
//   az ad signed-in-user show --query id -o tsv
param adminObjectId = '<your-entra-object-id>'

param cosmosMode = 'serverless'

// Check the model and version available in your region before deploying:
//   az cognitiveservices account list-models -g <rg> -n <foundry-account>
param modelName = 'gpt-4.1-mini'
param modelVersion = '<model-version>'
param modelCapacity = 10
