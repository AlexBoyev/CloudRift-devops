variable "vpc_cidr_block" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "subnet_cidr_blocks" {
  type        = list(string)
  description = "List of CIDR blocks for the public subnets"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones for the subnets"
}

variable "environment" {
  type = string
}
variable "project" {
  type = string
}

