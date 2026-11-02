// Reader for the alerting identity on one subscription (ARG reads for pull modules).
targetScope = 'subscription'

param principalId string

resource reader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  }
}
