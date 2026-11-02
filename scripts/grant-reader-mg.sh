#!/usr/bin/env bash
# Grant the alerting identity Reader on a management group (use with readerScope=none).
# Pull modules then see every subscription under the management group, including new ones.
#
#   scripts/grant-reader-mg.sh <management-group-id> <identity-principal-id>
#
# The principal id is the "identityPrincipalId" output of the main deployment.
set -euo pipefail

mg="${1:?management group id}"
principal="${2:?identity principal id}"

MSYS_NO_PATHCONV=1 az role assignment create \
  --assignee-object-id "$principal" \
  --assignee-principal-type ServicePrincipal \
  --role Reader \
  --scope "/providers/Microsoft.Management/managementGroups/$mg"
