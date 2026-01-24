data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  common_tags = {
    Owner   = var.owner
    Project = var.project
    Env     = var.environment
  }

  my_ipv4     = chomp(data.http.my_public_ip.response_body)
  my_ssh_cidr = "${local.my_ipv4}/32"

  # SECURITY GROUPS (no public Jenkins on 8080)
  security_groups = [
    {
      name = "ec2-stack-sg"

      ingress_rules = [
        # Public web access
        {
          description      = "Allow HTTP from IPv4"
          protocol         = "tcp"
          from_port        = 80
          to_port          = 80
          cidr_blocks      = ["0.0.0.0/0"]
          ipv6_cidr_blocks = []
        },
        {
          description      = "Allow HTTPS from IPv4"
          protocol         = "tcp"
          from_port        = 443
          to_port          = 443
          cidr_blocks      = ["0.0.0.0/0"]
          ipv6_cidr_blocks = []
        },

        # SSH locked to your current public IP (auto-detected)
        {
          description      = "Allow SSH from my public IP only (auto-detected)"
          protocol         = "tcp"
          from_port        = 22
          to_port          = 22
          cidr_blocks      = [local.my_ssh_cidr]
          ipv6_cidr_blocks = []
        }

        # IMPORTANT: Jenkins 8080 is intentionally NOT exposed.
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
}
