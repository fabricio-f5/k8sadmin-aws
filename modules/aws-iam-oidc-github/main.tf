# OIDC Provider — registra o GitHub como IdP confiável na conta AWS
#
# O provider é global por conta AWS (só pode existir um por URL).
# Se já existe de outro projeto, use create_oidc_provider = false
# no terragrunt.hcl para referenciar o existente via data source.

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.thumbprint_list

  tags = {
    Name = "github-actions-oidc-provider"
  }

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  oidc_provider_url = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].url : data.aws_iam_openid_connect_provider.github[0].url
}


# IAM Role — assumida pelo GitHub Actions via OIDC

resource "aws_iam_role" "github_actions" {
  name        = var.role_name
  description = "Role assumida pelo GitHub Actions via OIDC - repo: ${var.github_repo}"
  path        = "/ci/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGitHubOIDC"
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:${var.github_ref}"
          }
        }
      }
    ]
  })

  tags = {
    Name = var.role_name
  }
}

resource "aws_iam_role_policy_attachment" "extra_policies" {
  for_each = toset(var.policy_arns)

  role       = aws_iam_role.github_actions.name
  policy_arn = each.value
}
