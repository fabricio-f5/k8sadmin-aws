include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment = "dev"
}

terraform {
  source = "../../../modules/aws-security-group"
}

dependency "network" {
  config_path = "../network"

  mock_outputs = {
    vpc_id   = "vpc-mock"
    vpc_cidr = "10.0.0.0/16"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply"]
}

inputs = {
  name        = "k8sadmin-aws"
  environment = local.environment

  vpc_id   = dependency.network.outputs.vpc_id
  vpc_cidr = dependency.network.outputs.vpc_cidr
}
