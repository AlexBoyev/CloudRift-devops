# variable "aws_region" {
#   type = string
# }
variable "ami" {
  type = string
}

variable "instance_type" {
  type = string

}

variable "subnet_id" {
  type = string
}


variable "environment" {
  type = string
}
variable "project" {
  type = string
}


variable "algorithm" {
  type = string
}
variable "rsa" {
  type = string
}

# variable "private_content" {
#   type = string
# }
variable "private_filename" {
  type = string
}

# variable "public_content" {
#   type = string
# }
variable "public_filename" {
  type = string
}
# variable "pub_key" {
#   type = string
# }


variable "key_name" {
  type = string
}
variable "security_group_id" {
  type = string
}

variable "instance_name" {
  type = string
}

variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "root_volume_size" {
  type    = number
  default = 30
}