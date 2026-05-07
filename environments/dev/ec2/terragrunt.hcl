# ------------------------------------------------------------
# Provisiona múltiplas instâncias EC2 (cluster k8s)
# ------------------------------------------------------------
include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment = "dev"

  # Definição dos nós do cluster
  instances = {
    "master-1" = { instance_type = "t3.small" }
    "worker-1" = { instance_type = "t3.small" }
    "worker-2" = { instance_type = "t3.small" }
  }
}

terraform {
  source = "../../../modules/aws-ec2-instance"
}

# ------------------------------------------------------------
# Dependency — VPC / Subnet
# ------------------------------------------------------------
dependency "network" {
  config_path = "../network"

  mock_outputs = {
    subnet_id = "subnet-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply"]
}

# ------------------------------------------------------------
# Dependency — Security Group
# ------------------------------------------------------------
dependency "sg" {
  config_path = "../security-group"

  mock_outputs = {
    sg_id = "sg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply"]
}

dependency "iam" {
  config_path = "../iam"

  mock_outputs = {
    instance_profile_name = "mock-profile"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply"]
}

# ------------------------------------------------------------
# Inputs para o módulo EC2
# ------------------------------------------------------------
inputs = {
  environment          = local.environment
  instances            = local.instances
  iam_instance_profile = dependency.iam.outputs.instance_profile_name

  subnet_id            = dependency.network.outputs.subnet_id
  security_group_id    = dependency.sg.outputs.sg_id
}