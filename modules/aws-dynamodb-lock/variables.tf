variable "table_name" {
  description = "Nome da tabela DynamoDB usada para lock do Terraform state"
  type        = string
  default     = "terraform-state-lock"
}
