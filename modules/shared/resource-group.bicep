// Resource group for the push rules in a target subscription.
targetScope = 'subscription'

param name string
param location string
param tags object = {}

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: name
  location: location
  tags: tags
}
