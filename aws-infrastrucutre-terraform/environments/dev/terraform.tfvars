environment = "dev"
project     = "stack"
ssh_user    = "ubuntu"

# ********** VPC-Module **********
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

# ********** EC2-Module **********
ami           = "ami-0ecb62995f68bb549"
instance_name = "stack-Host"

instance_type    = "t3.large"
algorithm        = "RSA"
rsa              = 2048
key_name         = "stack-key-dev"
private_filename = "./terraform-modules/modules/ec2/keys/stack_key.pem"
public_filename  = "./terraform-modules/modules/ec2/keys/stack_key.pub"

# ******************** Security Group ********************
# Notes:
# - Jenkins port 8080 is NOT exposed publicly.
# - SSH (22) is not listed here anymore; it is auto-created in main.tf
#   using your current public IP (checkip.amazonaws.com).

security_groups = [
  {
    name = "ec2-stack-sg"

    ingress_rules = [
      {
        description      = "Allow HTTP from IPv4"
        protocol         = "tcp"
        from_port        = 80
        to_port          = 80
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = []
      },
      {
        description      = "Allow HTTP from IPv6"
        protocol         = "tcp"
        from_port        = 80
        to_port          = 80
        cidr_blocks      = []
        ipv6_cidr_blocks = ["::/0"]
      },

      {
        description      = "Allow HTTPS from IPv4"
        protocol         = "tcp"
        from_port        = 443
        to_port          = 443
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = []
      },
      {
        description      = "Allow HTTPS from IPv6"
        protocol         = "tcp"
        from_port        = 443
        to_port          = 443
        cidr_blocks      = []
        ipv6_cidr_blocks = ["::/0"]
      },

      # Keep port 2000 ONLY if you truly need it publicly. Otherwise remove it too.
      {
        description      = "Allow Custom TCP 2000 from IPv4"
        protocol         = "tcp"
        from_port        = 2000
        to_port          = 2000
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = []
      },
      {
        description      = "Allow Custom TCP 2000 from IPv6"
        protocol         = "tcp"
        from_port        = 2000
        to_port          = 2000
        cidr_blocks      = []
        ipv6_cidr_blocks = ["::/0"]
      }
    ]

    egress_rules = [
      {
        description      = "Allow All Traffic from IPv4"
        protocol         = "-1"
        from_port        = 0
        to_port          = 0
        cidr_blocks      = ["0.0.0.0/0"]
        ipv6_cidr_blocks = []
      },
    ]
  }
]
