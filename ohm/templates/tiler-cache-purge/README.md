## Tiler Purge Deployment

This chart deployment is responsible for running the script `image/tiler-cache/purge.py`, which handles purging tiles across different zoom levels. To execute this deployment, it is necessary to create a service account and attach it to the deployment. For example:

```yaml
# Create a ServiceAccount for managing Jobs and associated Pods
apiVersion: v1
kind: ServiceAccount
metadata:
  name: job-service-account
  namespace: default
---
# Create a ClusterRole with permissions for Jobs and Pods
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: job-manager-role
rules:
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["create", "list", "delete"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["list", "get"]
---
# Bind the ClusterRole to the ServiceAccount
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: job-manager-role-binding
subjects:
- kind: ServiceAccount
  name: job-service-account
  namespace: default
roleRef:
  kind: ClusterRole
  name: job-manager-role
  apiGroup: rbac.authorization.k8s.io
```