variable "name" {
  type        = string
  description = "Nome base dos recursos"
}

variable "environment" {
  type        = string
  description = "Ambiente: dev, staging ou prod"
}

variable "aws_region" {
  type        = string
  description = "Região AWS (usada nos nomes dos VPC Endpoints)"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block da VPC (ex: 10.0.0.0/16)"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR da subnet pública — usada pelo NAT Gateway"
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR da subnet privada — onde os nós k8s ficam"
}

variable "availability_zone" {
  type        = string
  description = "AZ onde as subnets serão criadas (ex: us-east-1a)"
}
