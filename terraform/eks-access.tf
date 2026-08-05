# Mapea el role de GitHub Actions a RBAC dentro del cluster via la API
# moderna de Access Entries (reemplaza el ConfigMap aws-auth legacy).

data "aws_caller_identity" "current" {}

locals {
  caller_arn = data.aws_caller_identity.current.arn

  # Cuando terraform corre asumiendo un role (ej. en CI via OIDC), el arn
  # del caller es una sesion STS (arn:aws:sts::...:assumed-role/<role>/<session>),
  # formato que EKS Access Entry no acepta. Access Entries solo aceptan el
  # ARN base del role/usuario IAM, asi que se normaliza aqui.
  caller_role_name      = try(regex("assumed-role/([^/]+)/", local.caller_arn)[0], null)
  normalized_caller_arn = local.caller_role_name != null ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.caller_role_name}" : local.caller_arn

  # Si quien corre terraform apply es el propio role de GitHub Actions, ya
  # tiene su access entry mas abajo — no crear uno duplicado. Se construye
  # el ARN esperado a partir del nombre (deterministico) en vez de leer
  # aws_iam_role.github_actions.arn directamente: ese valor es "unknown
  # hasta apply" en un create nuevo, lo que rompe el count aqui abajo.
  expected_github_actions_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-github-actions-deploy"
  needs_caller_access_entry        = local.normalized_caller_arn != local.expected_github_actions_role_arn
}

# El caller que corre terraform apply (bootstrap manual, ej. un humano)
# tambien necesita acceso admin al cluster para kubectl/debug local.
resource "aws_eks_access_entry" "terraform_caller" {
  count         = local.needs_caller_access_entry ? 1 : 0
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = local.normalized_caller_arn
}

resource "aws_eks_access_policy_association" "terraform_caller_admin" {
  count         = local.needs_caller_access_entry ? 1 : 0
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = local.normalized_caller_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.terraform_caller]
}

resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_actions.arn
}

resource "aws_eks_access_policy_association" "github_actions_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_actions.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.github_actions]
}
