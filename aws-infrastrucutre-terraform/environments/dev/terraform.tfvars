environment = "dev"
project     = "stack"
ssh_user    = "ubuntu"

# VPC
vpc_cidr_block = "172.20.0.0/16"

subnet_cidr_blocks = [
  "172.20.0.0/20",
  "172.20.16.0/20",
  "172.20.32.0/20",
  "172.20.48.0/20",
  "172.20.64.0/20",
  "172.20.80.0/20",
]

availability_zones = [
  "us-east-1a",
  "us-east-1b",
  "us-east-1c",
]

# EC2
ami           = "ami-0ecb62995f68bb549"
instance_name = "stack-Host"

instance_type    = "t3.large"
algorithm        = "RSA"
rsa              = 2048
key_name         = "stack-key-dev"
private_filename = "./terraform-modules/modules/ec2/keys/stack_key.pem"
public_filename  = "./terraform-modules/modules/ec2/keys/stack_key.pub"
