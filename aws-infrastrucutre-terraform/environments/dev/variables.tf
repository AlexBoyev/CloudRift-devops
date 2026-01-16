variable "region" {
  type        = string
  description = "AWS region"
}

variable "account_id" {
  type        = string
  description = "AWS account ID"
}

variable "aws_access_key" {
  type        = string
  description = "AWS Access Key ID"
  sensitive   = true
}

variable "aws_secret_key" {
  type        = string
  description = "AWS Secret Access Key"
  sensitive   = true
}

variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "vpc_cidr_block" {
  type = string
}

variable "subnet_cidr_blocks" {
  type = list(string)
}

variable "availability_zones" {
  type = list(string)
}

variable "ami" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "instance_name" {
  type = string
}

variable "key_name" {
  type = string
}

variable "algorithm" {
  type = string
}

variable "rsa" {
  type = string
}

variable "private_filename" {
  type = string
}

variable "public_filename" {
  type = string
}

variable "security_groups" {
  description = "A list of security group configurations"
  type = list(object({
    name = string,
    ingress_rules = list(object({
      from_port        = number,
      to_port          = number,
      protocol         = string,
      cidr_blocks      = list(string),
      ipv6_cidr_blocks = list(string),
      description      = string
    })),
    egress_rules = list(object({
      from_port        = number,
      to_port          = number,
      protocol         = string,
      cidr_blocks      = list(string),
      ipv6_cidr_blocks = list(string),
      description      = string
    })),
  }))
}
