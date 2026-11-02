// M2 Project Flash: VM and VMSS VM annotations from healthresourcechanges, classified by rules.json.
// ARG does not allow resources and computeresources in one query, so VM and VMSS run as two pull workflows.
targetScope = 'resourceGroup'

param prefix string
param location string = resourceGroup().location
param tags object = {}
param identityId string
param routerName string
param actionGroupId string = ''
param argScope object = {}
param excludedSubscriptionIds array = []
param bootstrapSilent bool = true
param fastLookback string = '2h'
param slowLookback string = '24h'
param enabled bool = true

var rules = filter(loadJsonContent('rules.json').rules, r => r.?enabled ?? true)
var nameRules = filter(rules, r => !empty(r.names))
var keywordRules = filter(rules, r => !empty(r.summaryKeywords))

// "base in~ ('A', 'B'), 'value'" per rule, then "isempty(name) and (summary contains 'x' or ...), 'value'" per keyword rule.
var nameConds = map(nameRules, r => 'base in~ (${join(map(r.names, n => '\'${n}\''), ', ')})')
var keywordConds = map(keywordRules, r => 'isempty(name) and (${join(map(r.summaryKeywords, k => 'summary contains \'${k}\''), ' or ')})')

var categoryCase = join(concat(
  map(range(0, length(nameRules)), i => '${nameConds[i]}, \'${nameRules[i].category}\''),
  map(range(0, length(keywordRules)), i => '${keywordConds[i]}, \'${keywordRules[i].category}\'')
), ', ')
var severityCase = join(concat(
  map(range(0, length(nameRules)), i => '${nameConds[i]}, \'${nameRules[i].severity}\''),
  map(range(0, length(keywordRules)), i => '${keywordConds[i]}, \'${keywordRules[i].severity}\'')
), ', ')
var initiatorCase = join(concat(
  map(range(0, length(nameRules)), i => '${nameConds[i]}, \'${nameRules[i].initiator}\''),
  map(range(0, length(keywordRules)), i => '${keywordConds[i]}, \'${keywordRules[i].initiator}\'')
), ', ')

func render(template string, category string, severity string, initiator string) string =>
  replace(replace(replace(template, '__CATEGORY__', category), '__SEVERITY__', severity), '__INITIATOR__', initiator)

var variants = [
  {
    suffix: 'vm'
    query: render(loadTextContent('query-vm.kql'), categoryCase, severityCase, initiatorCase)
  }
  {
    suffix: 'vmss'
    query: render(loadTextContent('query-vmss.kql'), categoryCase, severityCase, initiatorCase)
  }
]

module pull '../shared/pull-module.bicep' = [for v in variants: {
  name: '${prefix}-m2-flash-${v.suffix}'
  params: {
    name: '${prefix}-m2-flash-${v.suffix}'
    location: location
    tags: tags
    moduleName: 'm2-flash-${v.suffix}'
    query: v.query
    identityId: identityId
    routerName: routerName
    actionGroupId: actionGroupId
    argScope: argScope
    excludedSubscriptionIds: excludedSubscriptionIds
    bootstrapSilent: bootstrapSilent
    fastLookback: fastLookback
    slowLookback: slowLookback
    enabled: enabled
  }
}]

output workflowNames array = [for (v, i) in variants: pull[i].outputs.workflowName]
