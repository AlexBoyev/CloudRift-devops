# Database Module Outputs

output "endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.main.endpoint
}

output "address" {
  description = "The hostname of the RDS instance"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "The port the database is listening on"
  value       = aws_db_instance.main.port
}

output "database_name" {
  description = "The name of the database"
  value       = aws_db_instance.main.db_name
}

output "security_group_id" {
  description = "The security group ID for the RDS instance"
  value       = aws_security_group.rds.id
}

output "secret_arn" {
  description = "ARN of the secret containing database credentials"
  value       = aws_secretsmanager_secret.db_password.arn
}
