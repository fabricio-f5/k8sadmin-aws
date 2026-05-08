variable "bucket_name" {
  description = "Nome do bucket S3 usado pelo SSM Session Manager"
  type        = string
}

variable "retention_days" {
  description = "Dias para expirar os arquivos de sessão SSM"
  type        = number
  default     = 30
}
