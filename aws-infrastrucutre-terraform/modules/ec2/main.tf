########################################
# modules/ec2/main.tf
########################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

########################################
# Key pair
########################################
resource "tls_private_key" "stack_key" {
  algorithm = var.algorithm
  rsa_bits  = var.rsa
}

# Uses path provided by root variable
resource "local_file" "private_key" {
  content         = tls_private_key.stack_key.private_key_pem
  filename        = var.private_filename
  file_permission = "0400"
}

# Uses path provided by root variable
resource "local_file" "public_key" {
  content         = tls_private_key.stack_key.public_key_openssh
  filename        = var.public_filename
  file_permission = "0644"
}

resource "aws_key_pair" "stack_key" {
  public_key = tls_private_key.stack_key.public_key_openssh
  key_name   = var.key_name
}

########################################
# Launch Template
########################################
resource "aws_launch_template" "this" {
  name_prefix   = "${var.instance_name}-"
  image_id      = var.ami
  instance_type = var.instance_type
  key_name      = aws_key_pair.stack_key.key_name

  network_interfaces {
    subnet_id                   = var.subnet_id
    security_groups             = [var.security_group_id]
    associate_public_ip_address = true
  }

  block_device_mappings {
    device_name = var.root_device_name
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name        = var.instance_name
      Project     = var.project
      Owner       = var.owner
      Environment = var.environment
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name        = "${var.instance_name}-root"
      Project     = var.project
      Owner       = var.owner
      Environment = var.environment
    })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags = merge(var.tags, {
      Name        = "${var.instance_name}-eni"
      Project     = var.project
      Owner       = var.owner
      Environment = var.environment
    })
  }
}

########################################
# On-Demand EC2 Instance
########################################
resource "aws_instance" "this" {
  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tags = merge(var.tags, {
    Name        = var.instance_name
    Project     = var.project
    Owner       = var.owner
    Environment = var.environment
  })
}

########################################
# Bootstrap provisioning
########################################
resource "null_resource" "bootstrap" {
  depends_on = [aws_instance.this]
  connection {
    type = "ssh"
    # FIX 2: Connect using the Elastic IP, not the instance's old dynamic IP
    host        = aws_eip.this.public_ip
    user        = var.ssh_user
    private_key = tls_private_key.stack_key.private_key_pem
  }

  # Copy .env file
  provisioner "file" {
    source      = abspath("${path.root}/../.env")
    destination = "/home/${var.ssh_user}/.env"
  }

  # Copy bootstrap.sh
  provisioner "file" {
    source      = "${path.module}/bootstrap.sh"
    destination = "/home/${var.ssh_user}/bootstrap.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 30",

      # FIX: Remove Windows line endings from bootstrap.sh before running it
      "sed -i 's/\r$//' /home/${var.ssh_user}/bootstrap.sh",

      "chmod +x /home/${var.ssh_user}/bootstrap.sh",

      # Export variables
      "export DEVOPS_REPO_URL='${var.devops_repo_url}'",
      "export BACKEND_REPO_URL='${var.backend_repo_url}'",
      "export API_REPO_URL='${var.backend_repo_url}'",
      "export FRONTEND_REPO_URL='${var.frontend_repo_url}'",
      "export GIT_USERNAME='${var.git_username}'",
      "export GIT_PAT='${nonsensitive(var.git_pat)}'",

      "echo '--- STARTING BOOTSTRAP ---'",

      "sudo -E /home/${var.ssh_user}/bootstrap.sh",

      "if [ -d \"/home/${var.ssh_user}/new-devops-local\" ]; then cd /home/${var.ssh_user}/new-devops-local; else echo 'Directory not found' && exit 1; fi",

      # FIX: Sanitize the next script too, just in case
      "if [ -f devops-infra/scripts/devops-setup.sh ]; then sed -i 's/\r$//' devops-infra/scripts/devops-setup.sh; fi",

      "chmod +x devops-infra/scripts/devops-setup.sh",

      "echo '--- RUNNING DEVOPS SETUP ---'",
      "sudo -E devops-infra/scripts/devops-setup.sh dev true false false"
    ]
  }
}

resource "aws_eip" "this" {
  instance = aws_instance.this.id
  vpc      = true
  tags     = var.tags
}