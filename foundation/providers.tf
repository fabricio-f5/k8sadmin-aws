terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.92
        }
    }

    required_version = "~> 1.2"
}

provider "aws" {
    region = var.region

    default_tags {
        tags = {
            Project = "k8sadmin-aws"
            Environment = var.environment
            ManagedBy   = "terraform"
            Owner       = "fabricio peloso"
            Repository  = "git@github.com:fabricio-f5/k8sadmin-aws.git"
            CostCenter  = "engineering"
            Terraform   = "true"
        }
    }
}