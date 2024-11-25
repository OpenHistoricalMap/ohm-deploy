# Tiler Cache purging and seeding

This is a container that includes scripts to perform purge and seed operations. Each script must run on a different instance.

- Tiler seed script

Tiler seeding is a group of scripts aimed at generating tile cache for a specific zoom level, for example, from 1 to 7. The script will receive a GeoJSON of all the areas where tile cache generation is required for OHM tiles. This approach aims to reduce latency when a user starts interacting with OHM tiles.


- Tiler purge script

Script that reads an AWS SQS queue and creates a container to purge and seed the tiler cache for specific imposm expired files.


**Note**
To run these instances, a service account must be set up for the node that will execute them, as this container needs access to the AWS SQS service to function.


```sh
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

