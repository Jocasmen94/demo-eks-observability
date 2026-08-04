# demo-eks-observability

Demo simple: EKS desplegado con Terraform + CI/CD en GitHub Actions autenticado vía OIDC (sin access keys), más un stack de observabilidad (OpenTelemetry Operator + Prometheus/Grafana + Tempo) mostrando traces y métricas de un servicio instrumentado.

## Arquitectura

```
GitHub Actions --(OIDC, sin secrets estaticos)--> IAM Role --> terraform apply (VPC + EKS + node group)
                                                            --> kubectl apply (Collector + app demo)

demo-app --(OTLP)--> otel-collector --traces--> Tempo
                                     --metrics--> Prometheus --> Grafana
```

## Parte A — Infra (Terraform + EKS + OIDC)

### Bootstrap (una sola vez, local)

```bash
cd terraform
terraform init
terraform plan -var="github_repo=<org>/<repo>" -out=tfplan
terraform apply tfplan

gh secret set AWS_ROLE_ARN --repo <org>/<repo> --body "$(terraform output -raw github_actions_role_arn)"
```

Después de esto, cada push a `main` corre el workflow `.github/workflows/deploy.yml`:
1. Job `terraform` — asume el IAM role vía OIDC, `plan`/`apply`.
2. Job `deploy-app` — `aws eks update-kubeconfig` + `kubectl apply` del Collector y la app demo.

### Verificación

```bash
aws eks describe-cluster --name demo-eks-observability --query cluster.status
kubectl get nodes
```

## Parte B — Observability stack

Una vez el cluster existe y `kubectl` apunta a él:

```bash
./install.sh
```

Instala en orden: cert-manager → OpenTelemetry Operator → Tempo → kube-prometheus-stack (Prometheus + Grafana), luego aplica el CR `OpenTelemetryCollector` y la app demo instrumentada.

### Ver resultados

```bash
kubectl get pods -n observability

# Generar trafico
kubectl run curl-loop --image=curlimages/curl -n observability --restart=Never -- \
  sh -c "while true; do curl -s http://demo-app; sleep 1; done"

# Grafana
kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80
# usuario: admin / password: admin (definido en helm-values/kube-prometheus-stack-values.yaml)
```

En Grafana: **Explore → datasource Tempo** → buscar por `service.name = demo-app` para ver los traces. **Explore → datasource Prometheus** para las métricas exportadas por el Collector.

## Notas

- IRSA (`terraform/irsa.tf`) deja listo el patrón para que el Collector asuma un IAM role propio (ej. exportar a CloudWatch) sin credenciales estáticas en el pod — actualizar el ARN en `k8s/otel-collector.yaml` con el output `otel_collector_role_arn` si se usa.
- El role de GitHub Actions usa `PowerUserAccess` + `IAMFullAccess` solo para simplificar la demo — en un repo real se reemplaza por permisos scoped a los recursos exactos.
- Todo el stack es de un solo nodo / sin persistencia — pensado para levantar, probar y destruir (`terraform destroy`), no para producción.
