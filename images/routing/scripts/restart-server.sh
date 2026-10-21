#!/usr/bin/env bash
# Rolling restart of a Deployment through the Kubernetes API, the same as
# "kubectl rollout restart". Needs a ServiceAccount allowed to patch deployments.
set -euo pipefail
source "$(dirname "$0")/common.sh"

deployment=$1
sa=/var/run/secrets/kubernetes.io/serviceaccount
namespace=$(cat "$sa/namespace")
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

curl -fsS -o /dev/null -X PATCH \
  --cacert "$sa/ca.crt" \
  -H "Authorization: Bearer $(cat "$sa/token")" \
  -H "Content-Type: application/strategic-merge-patch+json" \
  "https://kubernetes.default.svc/apis/apps/v1/namespaces/$namespace/deployments/$deployment" \
  -d "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"kubectl.kubernetes.io/restartedAt\":\"$now\"}}}}}"
log "restarted deployment $deployment"
