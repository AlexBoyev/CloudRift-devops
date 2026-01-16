output "stack_ec2_sg_id" {
  value = aws_security_group.this["ec2-stack-sg"].id
}

output "security_group_ids" {
  description = "List of security group IDs created"
  value       = [for key, sg in aws_security_group.this : sg.id]
}
