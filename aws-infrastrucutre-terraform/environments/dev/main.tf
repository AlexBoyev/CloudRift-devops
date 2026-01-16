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

  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = module.vpc.subnet1

  instance_name     = var.instance_name
  security_group_id = module.sg.stack_ec2_sg_id

  environment = var.environment
  project     = var.project

  rsa       = var.rsa
  algorithm = var.algorithm

  private_filename = var.private_filename
  public_filename  = var.public_filename
  key_name         = var.key_name
}
