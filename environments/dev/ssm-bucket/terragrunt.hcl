include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/aws-s3-ssm"
}

inputs = {
  bucket_name    = "k8sadmin-aws-ssm-dev"
  retention_days = 30
}
