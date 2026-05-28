export KUBECONFIG=~/.kube/hetzner-ohm-staging.yaml

helm upgrade --install taginfo . \
  -f values.yaml \
  -f values.staging.template.yaml