output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "ec2_instance_id" {
  description = "EC2 Instance ID"
  value       = module.ec2.instance_id
}

output "ec2_public_ip" {
  description = "EC2 Instance Public IP"
  value       = module.ec2.public_ip
}

output "security_group_ids" {
  description = "Security Group IDs"
  value       = module.sg
}
