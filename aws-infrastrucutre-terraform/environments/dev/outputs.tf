output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "security_group_id" {
  description = "Security Group ID"
  value       = module.sg.stack_ec2_sg_id
}

output "ec2_instance_id" {
  description = "EC2 Instance ID"
  value       = module.ec2.stack_instance_id
}

output "ec2_public_ip" {
  description = "EC2 Instance Public IP"
  value       = module.ec2.stack_public_ip
}

output "ec2_private_ip" {
  description = "EC2 Instance Private IP"
  value       = module.ec2.stack_private_ip
}
