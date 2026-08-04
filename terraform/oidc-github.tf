# OIDC provider de GitHub Actions + role que asume CI para hacer
# terraform apply y deploy a EKS, sin access keys estaticas.

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = []

  lifecycle {
    ignore_changes = [thumbprint_list]
  }
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Esta cuenta tiene activado "immutable IDs" hardening de GitHub:
          # el sub claim real es repo:owner@ownerId/repo@repoId:... en vez de
          # repo:owner/repo:... — se usa wildcard para no hardcodear los IDs.
          # push a main: sub = repo:org@id/repo@id:ref:refs/heads/main
          # pull_request hacia main: sub = repo:org@id/repo@id:pull_request
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}",
            "repo:${var.github_repo}:pull_request",
            "repo:${split("/", var.github_repo)[0]}@*/${split("/", var.github_repo)[1]}@*:ref:refs/heads/${var.github_branch}",
            "repo:${split("/", var.github_repo)[0]}@*/${split("/", var.github_repo)[1]}@*:pull_request",
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "${var.project_name}-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
        ]
        Resource = "*"
      },
      {
        Sid    = "TerraformState"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "eks:Describe*",
          "eks:List*",
          "iam:Get*",
          "iam:List*",
          "sts:GetCallerIdentity",
        ]
        Resource = "*"
      }
    ]
  })
}

# Solo para esta demo: terraform apply necesita crear VPC/EKS/IAM roles.
# En un repo real esto se reemplaza por una policy scoped a los recursos exactos.
resource "aws_iam_role_policy_attachment" "github_actions_poweruser" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "github_actions_iam" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}
