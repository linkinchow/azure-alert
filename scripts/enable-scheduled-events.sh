#!/usr/bin/env bash
# M6 prerequisites: check (default) or enable Scheduled Events publishing to Event Grid and Resource Graph.
#
#   scripts/enable-scheduled-events.sh [--subscriptions "<id> <id> ..."] [--resource-group <rg>] [--include-vmss] [--apply]
#
# Without --apply nothing is changed: the script only reports, per subscription,
#   - the two feature flags (Microsoft.Compute/SendScheduledEventsPolicy, Microsoft.Maintenance/ScheduledEventsActivity),
#   - the Microsoft.Compute / Microsoft.Maintenance provider registration,
#   - how many VMs / VMSS have publishing enabled (scheduledEventsPolicy ... eventGridAndResourceGraph.enable).
# With --apply it registers the missing features / providers and enables publishing where it is missing:
#   - standalone VMs;
#   - availability sets that contain VMs (a VM in an availability set or a scale set cannot be set on its own; the
#     setting is made once on the availability set / scale set and applies to every VM in it);
#   - VMSS only with --include-vmss, and then only Flexible scale sets and Uniform scale sets whose upgrade policy is
#     Manual: changing the model of an Automatic / Rolling scale set may roll the instances, so those are skipped and listed.
# Platform-managed resources are never changed, only counted: anything in a managed resource group (the resource group
# has "managedBy", e.g. the AKS node resource group MC_*, Databricks) or tagged aks-managed-*. Changing AKS node pool
# scale sets directly is not supported by AKS and is overwritten by upgrades / scaling.
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
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
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
    print('\t'.join(str(r.get(k, '')) for k in ('id', 'vmKind', 'pubOn', 'upgrade', 'managed', 'members')))"
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
| where type in~ ('microsoft.compute/virtualmachines', 'microsoft.compute/virtualmachinescalesets', 'microsoft.compute/availabilitysets') $rg_filter
| extend rgKey = tolower(strcat(subscriptionId, '/', resourceGroup))
| join kind=leftouter (resourcecontainers | where type =~ 'microsoft.resources/subscriptions/resourcegroups'
    | project rgKey = tolower(strcat(subscriptionId, '/', name)), rgManagedBy = tostring(managedBy)) on rgKey
| extend pubOn = coalesce(tobool(properties.scheduledEventsPolicy.scheduledEventsAdditionalPublishingTargets.eventGridAndResourceGraph.enable), false)
| extend vmKind = case(type =~ 'microsoft.compute/availabilitysets', 'avset',
    type =~ 'microsoft.compute/virtualmachinescalesets', iff(tostring(properties.orchestrationMode) =~ 'Flexible', 'vmss-flexible', 'vmss-uniform'),
    isnotempty(tostring(properties.virtualMachineScaleSet.id)), 'vm-in-vmss',
    isnotempty(tostring(properties.availabilitySet.id)), 'vm-in-avset', 'vm')
| extend managed = case(isnotempty(rgManagedBy), tostring(split(rgManagedBy, '/')[-1]), tostring(tags) contains '\"aks-managed-', 'aks-managed tag', '-')
| extend avKey = tolower(id)
| join kind=leftouter (resources | where type =~ 'microsoft.compute/virtualmachines' and isnotempty(tostring(properties.availabilitySet.id))
    | summarize avVms = count() by avKey = tolower(tostring(properties.availabilitySet.id))) on avKey
| extend members = iff(vmKind == 'avset', max_of(coalesce(array_length(properties.virtualMachines), 0), coalesce(avVms, 0)), -1)
| project id, vmKind, pubOn, upgrade = coalesce(tostring(properties.upgradePolicy.mode), '-'), managed, members"
  rows=$(arg_rows "$sub" "$query")
  [ -n "$rows" ] || { echo "   no VM / VMSS"; continue; }

  # Not managed by a platform; empty availability sets are left out.
  own=$(printf '%s\n' "$rows" | awk -F'\t' '$5=="-" && !($2=="avset" && $6=="0")')
  for kind in vm avset vmss-flexible vmss-uniform; do
    total=$(printf '%s\n' "$own" | awk -F'\t' -v k="$kind" '$2==k' | wc -l | tr -d ' ')
    enabled=$(printf '%s\n' "$own" | awk -F'\t' -v k="$kind" '$2==k && $3=="True"' | wc -l | tr -d ' ')
    [ "$total" = "0" ] || echo "   $kind: $enabled / $total enabled"
  done
  inset=$(printf '%s\n' "$own" | awk -F'\t' '$2=="vm-in-vmss" || $2=="vm-in-avset"' | wc -l | tr -d ' ')
  [ "$inset" = "0" ] || echo "   ($inset VM(s) in scale sets / availability sets: covered by the setting on their scale set / availability set)"
  printf '%s\n' "$rows" | awk -F'\t' '$5!="-" && $2!~/^vm-in-/ && !($2=="avset" && $6=="0") {
      n++; if ($3=="True") e++; if (!($5 in seen)) {seen[$5]; owners = owners (owners == "" ? "" : ", ") $5} }
    END {if (n) printf "   skip, platform-managed - never changed (AKS node pools / managed resource groups): %d resource(s), %d already enabled; managed by: %s\n", n, e+0, owners}'

  printf '%s\n' "$own" | awk -F'\t' '$3!="True" && $2!~/^vm-in-/' | while IFS=$'\t' read -r id kind on upgrade managed members; do
    case "$kind" in
      vm|avset) ;;
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
