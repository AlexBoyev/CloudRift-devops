module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr_block     = var.vpc_cidr_block
  subnet_cidr_blocks = var.subnet_cidr_blocks
  availability_zones = var.availability_zones
  environment        = var.environment
  project            = var.project
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

  stack_certificate_domain_name                     = var.stack_certificate_domain_name
  stack_certificate_subject_alternative_names       = var.stack_certificate_subject_alternative_names
  stack_certificate_validation_method               = var.stack_certificate_validation_method
  stack_certificate_key_algorithm                   = var.stack_certificate_key_algorithm
  stack_certificate_transparency_logging_preference = var.stack_certificate_transparency_logging_preference
  private_filename                                  = var.private_filename
  public_filename                                   = var.public_filename
  key_name                                          = var.key_name
}

module "sg" {
  source          = "../../modules/sg"
  security_groups = var.security_groups
  vpc_id          = module.vpc.vpc_id
}
