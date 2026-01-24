data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}

module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr_block     = var.vpc_cidr_block
  subnet_cidr_blocks = var.subnet_cidr_blocks
  availability_zones = var.availability_zones
  environment        = var.environment
  project            = var.project
}

module "sg" {
  source          = "../../modules/sg"
  security_groups = var.security_groups
  vpc_id          = module.vpc.vpc_id
}

# SSH: allowed ONLY from your current public IP (auto-detected)
resource "aws_security_group_rule" "ssh_from_my_ip" {
  type              = "ingress"
  security_group_id = module.sg.stack_ec2_sg_id

  description = "Allow SSH from my public IP (auto-detected)"
  protocol    = "tcp"
  from_port   = 22
  to_port     = 22

  cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"]
}

module "ec2" {
  source = "../../modules/ec2"

  # --- CRITICAL FIX: Target the correct root device ---
  root_device_name = "/dev/sda1"
  root_volume_size = 40
  # ----------------------------------------------------

  ami               = var.ami
  instance_type     = var.instance_type
  subnet_id         = module.vpc.subnet1
  devops_repo_url   = var.devops_repo_url
  backend_repo_url  = var.backend_repo_url
  frontend_repo_url = var.frontend_repo_url
  git_username      = var.git_username
  git_pat           = var.git_pat
  instance_name     = var.instance_name
  security_group_id = module.sg.stack_ec2_sg_id

  environment = var.environment
  project     = var.project
  owner       = var.owner

  rsa       = var.rsa
  algorithm = var.algorithm

  private_filename = var.private_filename
  public_filename  = var.public_filename
  key_name         = var.key_name

  tags = local.common_tags
}
