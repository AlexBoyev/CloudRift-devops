variable "vpc_id" {
  description = "ID of the VPC where all security groups will be created"
  type        = string
}

variable "security_groups" {
  description = "A list of security group configurations"
  type = list(object({
    name = string,
    ingress_rules = list(object({
      from_port   = number,
      to_port     = number,
      protocol    = string,
      cidr_blocks = list(string),
    })),
    egress_rules = list(object({
      from_port   = number,
      to_port     = number,
      protocol    = string,
      cidr_blocks = list(string),
    })),
  }))
}
