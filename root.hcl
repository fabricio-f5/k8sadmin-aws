locals {
  aws_region = "us-east-1"
  project    = "k8sadmin-aws"

  # Extrai o ambiente do path do child: environments/<env>/...
  path_parts  = split("/", path_relative_to_include())
  environment = local.path_parts[1]

  tf_version  = "~> 1.10"
  aws_version = "~> 5.0"
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket       = "k8sadmin-aws-tfstate"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.aws_region
    encrypt        = true
    use_lockfile   = false
    dynamodb_table = "terraform-state-lock"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  default_tags {
    tags = {
      Project     = "${local.project}"
      ManagedBy   = "terragrunt"
      Environment = "${local.environment}"
    }
  }
}

terraform {
  required_version = "${local.tf_version}"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "${local.aws_version}"
    }
  }
}
EOF
}

terraform {
  extra_arguments "non_interactive" {
    commands  = get_terraform_commands_that_need_input()
    arguments = ["-input=false"]
  }

  extra_arguments "provider_cache" {
    commands = [
      "init",
      "plan",
      "apply",
      "destroy",
      "validate"
    ]

    env_vars = {
      TF_PLUGIN_CACHE_DIR = pathexpand("~/.terraform-plugin-cache")
    }
  }
}
