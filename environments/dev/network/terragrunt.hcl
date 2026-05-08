include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  environment = "dev"
}

terraform {
  source = "../../../modules/aws-vpc"
}

inputs = {
  name               = "k8sadmin-aws"
  environment        = local.environment
  aws_region         = "us-east-1"
  vpc_cidr           = "10.0.0.0/16"
  public_subnet_cidr = "10.0.1.0/24"
  private_subnet_cidr = "10.0.2.0/24"
  availability_zone  = "us-east-1a"
}
