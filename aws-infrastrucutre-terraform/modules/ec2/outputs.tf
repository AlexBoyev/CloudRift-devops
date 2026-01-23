########################################
# modules/ec2/outputs.tf
########################################

output "stack_instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.this.id
}

output "stack_public_ip" {
  description = "Dynamic public IP address of the EC2 instance"
  value       = aws_instance.this.public_ip
}

output "stack_public_dns" {
  description = "AWS-provided public DNS name (updates automatically with IP changes)"
  value       = aws_instance.this.public_dns
}

output "stack_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.this.private_ip
}

output "public_key_content" {
  description = "SSH public key content"
  value       = tls_private_key.stack_key.public_key_openssh
}

output "private_key_content" {
  description = "SSH private key content (sensitive)"
  value       = tls_private_key.stack_key.private_key_pem
  sensitive   = true
}

output "stack_key" {
  description = "SSH public key (alias for public_key_content)"
  value       = tls_private_key.stack_key.public_key_openssh
}

output "ssh_connection_command" {
  description = "Command to SSH into the instance using public DNS"
  value       = "ssh -i ${local_file.private_key.filename} ${var.ssh_user}@${aws_instance.this.public_dns}"
}

output "frontend_url" {
  description = "Frontend application URL"
  value       = "http://${aws_instance.this.public_dns}/"
}

output "jenkins_url" {
  description = "Jenkins URL"
  value       = "http://${aws_instance.this.public_dns}:8080/"
}

output "api_url" {
  description = "API URL"
  value       = "http://${aws_instance.this.public_dns}/api/"
}