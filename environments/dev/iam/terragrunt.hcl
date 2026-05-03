include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/aws-iam-ec2"
}

locals {
  environment = "dev"
}

inputs = {
  instance_name = "k8sadmin-${local.environment}"
}