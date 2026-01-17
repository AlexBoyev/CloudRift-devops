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

  # These work because we updated the module to accept them
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
