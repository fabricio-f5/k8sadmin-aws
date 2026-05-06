output "role_arn" {
  description = "ARN da IAM Role — usado no campo 'role-to-assume' do workflow"
  value       = aws_iam_role.github_actions.arn
}

output "role_name" {
  description = "Nome da IAM Role criada"
  value       = aws_iam_role.github_actions.name
}

output "oidc_provider_arn" {
  description = "ARN do OIDC Provider registrado na conta AWS"
  value       = local.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "URL do OIDC Provider"
  value       = local.oidc_provider_url
}
