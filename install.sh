#!/usr/bin/env bash
set -euo pipefail

# Instala el stack de observabilidad (cert-manager, OTel Operator, Tempo,
# kube-prometheus-stack) y despliega el Collector + app demo.
# Requiere: kubectl apuntando ya al cluster EKS (aws eks update-kubeconfig).

NAMESPACE=observability
export OTEL_COLLECTOR_ROLE_ARN
OTEL_COLLECTOR_ROLE_ARN=$(cd terraform && terraform output -raw otel_collector_role_arn)

echo ">> Creando namespace ${NAMESPACE}"
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo ">> Instalando cert-manager"
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true

echo ">> Esperando cert-manager listo"
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=120s

echo ">> Instalando OpenTelemetry Operator"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts --force-update
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace "${NAMESPACE}"

echo ">> Instalando Tempo"
helm repo add grafana https://grafana.github.io/helm-charts --force-update
helm upgrade --install tempo grafana/tempo \
  --namespace "${NAMESPACE}" \
  -f helm-values/tempo-values.yaml

echo ">> Instalando kube-prometheus-stack (Prometheus + Grafana)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace "${NAMESPACE}" \
  -f helm-values/kube-prometheus-stack-values.yaml

echo ">> Esperando CRD del OTel Operator"
kubectl wait --for=condition=Established crd/opentelemetrycollectors.opentelemetry.io --timeout=60s

echo ">> Desplegando Collector + app demo"
envsubst < k8s/otel-collector.yaml | kubectl apply -f -
kubectl apply -f k8s/demo-app.yaml

echo ">> Listo. Verifica con: kubectl get pods -n ${NAMESPACE}"
