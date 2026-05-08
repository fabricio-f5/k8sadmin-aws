variable "instance_name" {
  description = "Nome da instância EC2 — usado como prefixo nos recursos IAM"
  type        = string
}

variable "ssm_bucket_arn" {
  description = "ARN do bucket S3 usado pelo SSM Session Manager"
  type        = string
}

variable "policy_arns" {
  description = "Lista de policies IAM a serem anexadas à Role da EC2"
  type        = list(string)

  default = [
    # Acesso via SSM (ESSENCIAL - sem SSH)
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",

    # Permite pull de imagens do ECR (Kubernetes / containers)
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ]
}