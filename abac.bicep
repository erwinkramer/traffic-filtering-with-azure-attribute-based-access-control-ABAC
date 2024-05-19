/**

Azure attribute-based access control (Azure ABAC) module for storage accounts.

Please read https://learn.microsoft.com/en-us/azure/role-based-access-control/conditions-overview
See condition formats here: https://learn.microsoft.com/en-us/azure/role-based-access-control/conditions-format

In this template; the 'principalId' param gets assigned the 'Storage Blob Data Reader' role, but if this identity tries to read a blob, 
all the following properties on the storage account (or deeper level) have to be true:
- blob has to be the current version
- blob tag key and value have to be equal to 'tagKey' and 'tagValue' param
- container metadata key and value have to be equal to 'metadataKey' and 'metadataValue' param
- the connection has to be made from the 'allowedPrivateEndpointId' param
- the storage account name has to be the 'storageAccountName' param

Run the module individually with:
az login
az deployment group create --template-file abac.bicep --resource-group rg-guanchen

**/

param storageAccountName string = 'onestoragesystem'

param principalId string = '18f89f96-6a81-41d8-90ff-8890495f147a'
param principalType string = 'ServicePrincipal'

param tagKey string = 'project'
param tagValue string = 'helloABAC'

param metadataKey string = 'project'
param metadataValue string = 'helloABAC'

param allowedPrivateEndpointId string = '/subscriptions/92b2afd7-e3db-4660-90c5-0da4aebf53d4/resourceGroups/vnet-92b2afd7-northeurope-55-rg/providers/Microsoft.Network/privateEndpoints/guanchensynapse-007.AzureBlobStorage371'

//private variable used for condition actions and expressions
var _containerType = 'Microsoft.Storage/storageAccounts/blobServices/containers'

@description('''
Actions you want to allow if the condition is true. 
Here, 'Blob.List' is exempted from this rule, so it is always allowed to list blobs, regardless of the condition expressions.
''')
var conditionActions = {
  blobReadExceptBlobList: '!(ActionMatches{\'${_containerType}/blobs/read\'} AND NOT SubOperationMatches{\'Blob.List\'})'
}

@description('''
If the expressions evaluate to true, access is allowed to the selected actions.
So for example, using 'currentBlobVersion' means you can only access a blob if the blob is the current version, and not a previous one.
''')
var conditionExpressions = {
  currentBlobVersion: '@Resource[${_containerType}/blobs:isCurrentVersion] BoolEquals true'
  equalBlobTag: '@Resource[${_containerType}/blobs/tags:${tagKey}<$key_case_sensitive$>] StringEqualsIgnoreCase \'${tagValue}\''
  equalContainerMetadata: '@Resource[${_containerType}/metadata:${metadataKey}] StringEqualsIgnoreCase \'${metadataValue}\''
  equalPrivateEndpoint: '@Environment[Microsoft.Network/privateEndpoints] StringEqualsIgnoreCase \'${allowedPrivateEndpointId}\''
  equalAccountName: '@Resource[Microsoft.Storage/storageAccounts:name] StringEquals \'${storageAccountName}\''
}

var roleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1' //Storage Blob Data Reader

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-04-01' existing = {
  name: storageAccountName
}

resource roleAssignmentABAC 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('${principalId}${roleId}${storageAccountName}')
  scope: storageAccount
  properties: {
    condition: '((${conditionActions.blobReadExceptBlobList}) OR (${conditionExpressions.equalAccountName} AND ${conditionExpressions.equalPrivateEndpoint} AND ${conditionExpressions.currentBlobVersion} AND ${conditionExpressions.equalBlobTag} AND ${conditionExpressions.equalContainerMetadata}))'
    conditionVersion: '2.0'
    description: '''
ABAC Assignment.
If the condition with the expressions are met, the access as specified by the roleDefinitionId is allowed.'''
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
  }
}
