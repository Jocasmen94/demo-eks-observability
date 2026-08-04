variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre base del proyecto, usado como prefijo de recursos"
  type        = string
  default     = "demo-eks-observability"
}

variable "cluster_version" {
  description = "Version de Kubernetes para el cluster EKS"
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "CIDR block de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "github_repo" {
  description = "Repo de GitHub autorizado a asumir el role de CI (formato org/repo)"
  type        = string
}

variable "github_branch" {
  description = "Branch autorizado a asumir el role de CI"
  type        = string
  default     = "main"
}

variable "node_instance_type" {
  description = "Instance type del node group EKS"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Numero deseado de nodos"
  type        = number
  default     = 1
}
