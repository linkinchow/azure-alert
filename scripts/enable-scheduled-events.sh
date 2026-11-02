#!/usr/bin/env bash
# M6 prerequisites: check (default) or enable Scheduled Events publishing to Event Grid and Resource Graph.
#
#   scripts/enable-scheduled-events.sh [--subscriptions "<id> <id> ..."] [--resource-group <rg>] [--include-vmss] [--apply]
#
# Without --apply nothing is changed: the script only reports, per subscription,
#   - the two feature flags (Microsoft.Compute/SendScheduledEventsPolicy, Microsoft.Maintenance/ScheduledEventsActivity),
#   - the Microsoft.Compute / Microsoft.Maintenance provider registration,
#   - how many VMs / VMSS have publishing enabled (scheduledEventsPolicy ... eventGridAndResourceGraph.enable).
# With --apply it registers the missing features / providers and enables publishing on the VMs that do not have it.
# VMSS are only touched with --include-vmss, and then only Flexible scale sets and Uniform scale sets whose upgrade policy
# is Manual: changing the model of an Automatic / Rolling scale set may roll the instances, so those are skipped and listed.
# User-initiated reboot / redeploy auto-approval is left as it is.
# Default subscriptions: every subscription the signed-in account can see.
set -euo pipefail
export MSYS_NO_PATHCONV=1

subs=""
rg=""
include_vmss=false
apply=false
while [ $# -gt 0 ]; do
  case "$1" in
    --subscriptions) subs="$2"; shift 2 ;;
    --resource-group) rg="$2"; shift 2 ;;
    --include-vmss) include_vmss=true; shift ;;
    --apply) apply=true; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$subs" ] || subs=$(az account list --query "[?state=='Enabled'].id" -o tsv)

api="2025-04-01"
body='{"properties":{"scheduledEventsPolicy":{"scheduledEventsAdditionalPublishingTargets":{"eventGridAndResourceGraph":{"enable":true,"scheduledEventsApiVersion":"2020-07-01"}}}}}'
rg_filter=""
[ -z "$rg" ] || rg_filter="| where resourceGroup =~ '$rg'"

# Paged ARG query for one subscription; prints one tab-separated row per resource.
arg_rows() {
  local sub="$1" query="$2" token="" out
  while :; do
    if [ -n "$token" ]; then
      out=$(az graph query -q "$query" --subscriptions "$sub" --first 1000 --skip-token "$token" -o json)
    else
      out=$(az graph query -q "$query" --subscriptions "$sub" --first 1000 -o json)
    fi
    echo "$out" | az_json_rows
    token=$(echo "$out" | python -c "import json,sys; print(json.load(sys.stdin).get('skip_token') or '')")
    [ -n "$token" ] || break
  done
}
az_json_rows() {
  python -c "
import json, sys
for r in json.load(sys.stdin)['data']:
    r['pubOn'] = 'True' if r.get('pubOn') in (True, 1, 'true', 'True') else 'False'  # az graph returns 1 / 0
    print('\t'.join(str(r.get(k, '')) for k in ('id', 'vmKind', 'pubOn', 'upgrade')))"
}

for sub in $subs; do
  echo "== subscription $sub"
  for f in Microsoft.Compute/SendScheduledEventsPolicy Microsoft.Maintenance/ScheduledEventsActivity; do
    ns=${f%%/*}; name=${f##*/}
    state=$(az feature show --namespace "$ns" --name "$name" --subscription "$sub" --query properties.state -o tsv 2>/dev/null || echo NotRegistered)
    echo "   feature $f: $state"
    if $apply && [ "$state" != "Registered" ] && [ "$state" != "Registering" ]; then
      az feature register --namespace "$ns" --name "$name" --subscription "$sub" -o none
      echo "     -> registration requested (wait until Registered, then run this script again)"
    fi
  done
  for ns in Microsoft.Compute Microsoft.Maintenance; do
    state=$(az provider show --namespace "$ns" --subscription "$sub" --query registrationState -o tsv 2>/dev/null || echo NotRegistered)
    echo "   provider $ns: $state"
    if $apply && [ "$state" != "Registered" ]; then
      az provider register --namespace "$ns" --subscription "$sub" -o none
      echo "     -> provider registration requested"
    fi
  done

  query="resources
| where type in~ ('microsoft.compute/virtualmachines', 'microsoft.compute/virtualmachinescalesets') $rg_filter
| extend pubOn = coalesce(tobool(properties.scheduledEventsPolicy.scheduledEventsAdditionalPublishingTargets.eventGridAndResourceGraph.enable), false)
| extend vmKind = iff(type =~ 'microsoft.compute/virtualmachines', 'vm', iff(tostring(properties.orchestrationMode) =~ 'Flexible', 'vmss-flexible', 'vmss-uniform'))
| project id, vmKind, pubOn, upgrade = coalesce(tostring(properties.upgradePolicy.mode), '-')"
  rows=$(arg_rows "$sub" "$query")
  [ -n "$rows" ] || { echo "   no VM / VMSS"; continue; }

  for kind in vm vmss-flexible vmss-uniform; do
    total=$(printf '%s\n' "$rows" | awk -F'\t' -v k="$kind" '$2==k' | wc -l | tr -d ' ')
    enabled=$(printf '%s\n' "$rows" | awk -F'\t' -v k="$kind" '$2==k && $3=="True"' | wc -l | tr -d ' ')
    [ "$total" = "0" ] || echo "   $kind: $enabled / $total enabled"
  done

  printf '%s\n' "$rows" | awk -F'\t' '$3!="True"' | while IFS=$'\t' read -r id kind on upgrade; do
    case "$kind" in
      vm) ;;
      vmss-flexible) $include_vmss || { echo "   skip (use --include-vmss): $id"; continue; } ;;
      vmss-uniform)
        $include_vmss || { echo "   skip (use --include-vmss): $id"; continue; }
        if [ "$upgrade" != "Manual" ]; then echo "   skip (upgrade policy $upgrade, enable it in a maintenance window): $id"; continue; fi ;;
    esac
    if $apply; then
      az rest --method patch --url "https://management.azure.com${id}?api-version=${api}" --body "$body" -o none && echo "   enabled: $id"
    else
      echo "   not enabled: $id"
    fi
  done
done
$apply || echo "(check only - nothing was changed; add --apply to enable)"
