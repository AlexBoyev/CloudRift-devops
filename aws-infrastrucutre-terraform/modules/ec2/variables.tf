variable "devops_repo_url" { type = string }
variable "backend_repo_url" { type = string }
variable "frontend_repo_url" { type = string }

variable "git_username" { type = string }
variable "git_pat" {
  type      = string
  sensitive = true
}

############################
# Core EC2 inputs
############################
variable "ami" { type = string }
variable "instance_type" { type = string }
variable "instance_name" { type = string }

variable "subnet_id" { type = string }
variable "security_group_id" { type = string }

# FIX: Added default so it doesn't fail if root forgets to pass it
variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "algorithm" { type = string }
variable "rsa" { type = number }
variable "key_name" { type = string }

# FIX: Added variables that your root main.tf is passing
variable "environment" { type = string }
variable "project" { type = string }
variable "owner" { type = string }

variable "private_filename" { type = string }
variable "public_filename" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}

############################
# Root disk controls
############################
variable "root_volume_size" {
  type        = number
  description = "Root EBS volume size in GB"
  default     = 40
}

variable "root_volume_type" {
  type        = string
  description = "Root EBS volume type"
  default     = "gp3"
}

variable "root_device_name" {
  type        = string
  description = "Root device name for block mapping"
  default     = "/dev/xvda"
}