// Test helper: a fake Feishu bot webhook (Logic App). The reply depends on the "mode" query parameter:
//   mode=always -> {"code":11232} (rate limited)   mode=half -> rate limited about half of the time
//   mode=bad    -> {"code":9499} (bad request)      anything else -> {"code":0} (success)
// Used to test the Router's retry on rate limiting without sending real messages. Not part of the solution.
param name string = 'mock-feishu'
param location string = resourceGroup().location
param tags object = {}

var mode = '@coalesce(triggerOutputs()?[\'queries\']?[\'mode\'], \'ok\')'

resource mock 'Microsoft.Logic/workflows@2019-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            method: 'POST'
          }
        }
      }
      actions: {
        Mode: {
          type: 'Compose'
          inputs: mode
          runAfter: {}
        }
        Reply: {
          type: 'Response'
          kind: 'Http'
          inputs: {
            statusCode: 200
            headers: {
              'Content-Type': 'application/json'
            }
            body: '@if(or(equals(outputs(\'Mode\'), \'always\'), and(equals(outputs(\'Mode\'), \'half\'), equals(rand(0, 2), 0))), json(\'{"code":11232,"msg":"frequency limited (mock)"}\'), if(equals(outputs(\'Mode\'), \'bad\'), json(\'{"code":9499,"msg":"Bad Request (mock)"}\'), json(\'{"code":0,"msg":"success (mock)"}\')))'
          }
          runAfter: {
            Mode: [
              'Succeeded'
            ]
          }
        }
      }
    }
  }
}

output callbackUrl string = listCallbackUrl('${mock.id}/triggers/manual', '2019-05-01').value
