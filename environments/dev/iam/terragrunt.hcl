include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/aws-iam-ec2"
}

locals {
  environment = "dev"
}

dependency "ssm_bucket" {
  config_path = "../ssm-bucket"

  mock_outputs = {
    bucket_arn = "arn:aws:s3:::mock-ssm-bucket"
  }
  mock_outputs_allowed_terraform_commands = ["init", "plan", "apply"]
}

inputs = {
  instance_name  = "k8sadmin-${local.environment}"
  ssm_bucket_arn = dependency.ssm_bucket.outputs.bucket_arn
}