include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/aws-iam-oidc-github"
}

inputs = {
  # O OIDC provider já existe nesta conta AWS (global por conta)
  create_oidc_provider = false

  # Repositório GitHub no formato "org/repo"
  github_repo = "fabricio-f5/k8sadmin-aws"

  # dev: qualquer branch pode assumir a role
  # prod: trocar por "ref:refs/heads/main" para restringir
  github_ref = "*"

  role_name = "k8sadmin-github-actions"

  # Políticas necessárias para o Terragrunt gerenciar a infra deste projeto
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess",    # EC2 + VPC + Security Groups
    "arn:aws:iam::aws:policy/AmazonS3FullAccess",     # Terraform state + módulo S3
    "arn:aws:iam::aws:policy/IAMFullAccess",          # Criar roles e instance profiles
  ]
}
