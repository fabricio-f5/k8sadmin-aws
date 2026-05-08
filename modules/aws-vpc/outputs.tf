output "vpc_id" {
  description = "ID da VPC"
  value       = aws_vpc.this.id
}

output "public_subnet_id" {
  description = "ID da subnet pública (NAT Gateway)"
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID da subnet privada (nós k8s)"
  value       = aws_subnet.private.id
}

output "subnet_id" {
  description = "Alias para private_subnet_id — compatibilidade com dependências existentes"
  value       = aws_subnet.private.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}
