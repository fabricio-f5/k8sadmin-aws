include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment = "dev"
}

terraform {
  source = "../../../modules/aws-security-group"
}

# ------------------------------------------------------------
# Dependency — VPC / Subnet
# ------------------------------------------------------------
dependency "network" {
  config_path = "../network"

  mock_outputs = {
    subnet_id = "subnet-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan"]
}

inputs = {
  name              = "k8sadmin-aws"
  environment       = local.environment
  vpc_cidr          = "10.0.0.0/16"
  subnet_cidr       = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  vpc_id = dependency.network.outputs.vpc_id
  vpc_cidr = dependency.network.outputs.vpc_cidr
}