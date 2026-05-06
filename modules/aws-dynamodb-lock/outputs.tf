output "table_name" {
  description = "Nome da tabela DynamoDB de lock"
  value       = aws_dynamodb_table.lock.name
}

output "table_arn" {
  description = "ARN da tabela DynamoDB de lock"
  value       = aws_dynamodb_table.lock.arn
}
