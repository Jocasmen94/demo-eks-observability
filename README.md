# demo-eks-observability

Demo: EKS desplegado con Terraform + CI/CD en GitHub Actions autenticado vía OIDC (sin access keys), más un stack de observabilidad (OpenTelemetry Operator + Prometheus/Grafana + Tempo) mostrando traces y métricas de un servicio instrumentado.

## Arquitectura

```
GitHub Actions --(OIDC, sin secrets estaticos)--> IAM Role --> terraform apply (VPC + EKS + node group)
                                                            --> kubectl apply (Collector + app demo)

demo-app --(OTLP)--> otel-collector --traces--> Tempo
                                     --metrics--> Prometheus --> Grafana
```

Flujo: **paso 1-10 se corren manual una sola vez** (bootstrap). De ahí en adelante, cualquier cambio a `terraform/*.tf` o `k8s/*.yaml` se hace con PR + push a `main` y el pipeline (`.github/workflows/deploy.yml`) corre solo.

---

## Paso 0 — Prerequisitos locales

```bash
aws --version          # AWS CLI v2
terraform --version    # >= 1.10
kubectl version --client
helm version
gh --version
```

Confirmar identidad y cuenta AWS activa:

```bash
aws sts get-caller-identity
```

Confirmar que el bucket de state ya existe (compartido con `demo-ecs-fargate`, distinto `key`):

```bash
aws s3api head-bucket --bucket boxful-demo-tfstate-460852142662
```

---

## Paso 1 — terraform init

```bash
cd terraform
terraform init
```

## Paso 2 — terraform validate + fmt

```bash
terraform fmt -check
terraform validate
```

## Paso 3 — terraform plan

`github_repo` ya tiene default en `variables.tf` (`Jocasmen94/demo-eks-observability`) — no hace falta pasar `-var`:

```bash
terraform plan -out=tfplan
```

Revisar el plan antes de aplicar — debe crear: VPC, subnets, NAT, cluster EKS, node group, OIDC provider de GitHub, IAM role de CI, access entry, OIDC provider del cluster (IRSA).

## Paso 4 — terraform apply

```bash
terraform apply tfplan
```

Tarda ~10-15 min (EKS control plane es lento en crear).

## Paso 5 — setear el secret en GitHub (una sola vez, inevitable)

El pipeline necesita este secret para poder autenticarse por primera vez —
antes de que exista, no hay pipeline que lo genere solo. Es el único valor
que se mueve a mano en todo el flujo:

```bash
gh secret set AWS_ROLE_ARN --repo Jocasmen94/demo-eks-observability --body "$(terraform output -raw github_actions_role_arn)"
```

## Paso 6 — conectar kubectl al cluster

```bash
aws eks update-kubeconfig --name demo-eks-observability --region us-east-1
kubectl get nodes
```

`otel_collector_role_arn` (usado en `k8s/otel-collector.yaml`) **no se toca a mano** —
tanto `install.sh` como el pipeline lo leen de `terraform output` y lo inyectan
con `envsubst` en el momento de aplicar el manifest.

---

## Paso 7 — instalar el stack de observabilidad

```bash
cd ..
./install.sh
```

Instala en orden: cert-manager → OpenTelemetry Operator → Tempo → kube-prometheus-stack (Prometheus + Grafana), luego aplica el CR `OpenTelemetryCollector` y la app demo instrumentada.

## Paso 8 — verificar pods

```bash
kubectl get pods -n observability
```

Todo debe quedar `Running`.

## Paso 9 — generar tráfico

```bash
kubectl run curl-loop --image=curlimages/curl -n observability --restart=Never -- \
  sh -c "while true; do curl -s http://demo-app; sleep 1; done"
```

## Paso 10 — abrir Grafana

```bash
kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80
```
otel collector prometheusreceiver y prometheusexporter

Ir a `http://localhost:3000` — usuario `admin` / password `admin` (definido en `helm-values/kube-prometheus-stack-values.yaml`).

- **Explore → datasource Tempo** → buscar `service.name = demo-app` para ver traces.
- **Explore → datasource Prometheus** → ver métricas exportadas por el Collector (`job="otel-collector"`).

---

## A partir de aquí: todo vía pipeline (PR + merge)

Cualquier cambio a Terraform o a los manifests de `k8s/` se hace así:

```bash
git checkout -b feat/mi-cambio
# editar terraform/*.tf o k8s/*.yaml
git add .
git commit -m "mensaje del cambio"
git push origin feat/mi-cambio
gh pr create --base main --fill
```

Al abrir el PR, el workflow corre `terraform plan` y **comenta el PR con el plan completo** (colapsado en un `<details>`) — se revisa ahí antes de aprobar. Al hacer merge a `main`:
1. Job `terraform` — asume el IAM role vía OIDC, corre `plan` de nuevo y `apply`.
2. Job `deploy-app` — `aws eks update-kubeconfig` + `kubectl apply` del Collector (con el ARN de IRSA inyectado vía `envsubst`) y la app demo.

No se vuelve a correr `terraform apply` ni `kubectl apply` manual después del bootstrap, salvo debugging.

---

## Verificación rápida de infra

```bash
aws eks describe-cluster --name demo-eks-observability --query cluster.status
kubectl get nodes
kubectl get pods -A
```

---

## Destruir todo (evitar costos)

```bash
kubectl delete namespace observability
cd terraform
terraform destroy
```

---

## Notas

- IRSA (`terraform/irsa.tf`) deja listo el patrón para que el Collector asuma un IAM role propio (ej. exportar a CloudWatch) sin credenciales estáticas en el pod.
- El role de GitHub Actions usa `PowerUserAccess` + `IAMFullAccess` solo para simplificar la demo — en un repo real se reemplaza por permisos scoped a los recursos exactos.
- Todo el stack es de un solo nodo / sin persistencia — pensado para levantar, probar y destruir, no para producción.
- Costo aproximado mientras está arriba: EKS control plane ~$0.10/hr + 1 nodo t3.medium spot (~$0.01-0.02/hr). Destruir apenas termines la demo.
