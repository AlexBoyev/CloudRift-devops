output "stack_instance_id" {
  value = aws_instance.this.id
}

output "stack_public_ip" {
  value = aws_instance.this.public_ip
}

output "stack_private_ip" {
  value = aws_instance.this.private_ip
}

output "public_key_content" {
  value = tls_private_key.stack_key.public_key_openssh
}

output "private_key_content" {
  value = tls_private_key.stack_key.private_key_pem
}

output "stack_key" {
  value = tls_private_key.stack_key.public_key_openssh
}
