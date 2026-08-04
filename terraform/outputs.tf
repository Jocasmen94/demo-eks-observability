output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "otel_collector_role_arn" {
  value = aws_iam_role.otel_collector.arn
}
