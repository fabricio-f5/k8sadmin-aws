include "root" {
  path = find_in_parent_folders("bootstrap/root.hcl")
}

terraform {
  source = "../../modules/aws-dynamodb-lock"
}

inputs = {
  table_name = "terraform-state-lock"
}
