variable "instances" {
  description = "Mapa de instâncias a serem criadas"
  type = map(object({
    instance_type = string
  }))
}

variable "instance_name" {
  description = "Prefixo base para nome das instâncias (opcional)"
  type        = string
  default     = "ec2"
}

variable "iam_instance_profile" {
  description = "Instance Profile associado à EC2"
  type        = string
  default     = null
}

variable "environment" {
  description = "Nome do ambiente"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID"
  type        = string
}

variable "security_group_id" {
  description = "Security Group ID"
  type        = string
}