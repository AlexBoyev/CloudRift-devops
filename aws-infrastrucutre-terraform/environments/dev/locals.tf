locals {
  common_tags = {
    Owner   = var.owner
    Project = var.project
    Env     = var.environment
  }
}
