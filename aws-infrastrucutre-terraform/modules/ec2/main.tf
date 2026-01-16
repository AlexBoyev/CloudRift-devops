########################################
# Create a new key pair (TLS -> AWS KeyPair)
########################################

resource "tls_private_key" "stack_key" {
  algorithm = var.algorithm
  rsa_bits  = var.rsa
}

resource "local_file" "private_key" {
  content  = tls_private_key.stack_key.private_key_pem
  filename = "${path.module}/keys/stack_key.pem"
}

resource "local_file" "public_key" {
  content  = tls_private_key.stack_key.public_key_openssh
  filename = "${path.module}/keys/stack_key.pub"
}

resource "aws_key_pair" "stack_key" {
  public_key = tls_private_key.stack_key.public_key_openssh
  key_name   = var.key_name
}

########################################
# Launch Template
# - Keep ENI + security group here
# - Keep tag_specifications here (Owner must be in request)
# - Do NOT rely on LT for instance_type for Spot request
########################################

resource "aws_launch_template" "this" {
  name_prefix = "${var.instance_name}-"

  # Keep AMI + key here
  image_id = var.ami
  key_name = aws_key_pair.stack_key.key_name

  network_interfaces {
    subnet_id                   = var.subnet_id
    security_groups             = [var.security_group_id]
    associate_public_ip_address = true
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name    = var.instance_name
      Owner   = var.owner
      Env     = var.environment
      Project = var.project
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Owner   = var.owner
      Env     = var.environment
      Project = var.project
    }
  }
}

########################################
# Spot Instance Request
# - Provide instance_type explicitly to satisfy AWS requirement
########################################

resource "aws_spot_instance_request" "this" {
  wait_for_fulfillment = true

  ami           = var.ami
  instance_type = var.instance_type
  key_name      = aws_key_pair.stack_key.key_name
  subnet_id     = var.subnet_id

  vpc_security_group_ids = [var.security_group_id]

  # Request-time tags (good practice), but IAM requires request tags for RunInstances.
  # We also satisfy that via LT tag_specifications above.
  tags = {
    Name    = var.instance_name
    Owner   = var.owner
    Env     = var.environment
    Project = var.project
  }

  # Optional: if you want to use LT for additional settings you can keep this,
  # but AWS already has all required fields above.
  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }
}

########################################
# Lookup the created instance (so we can get IPs for provisioning)
########################################

data "aws_instance" "this" {
  instance_id = aws_spot_instance_request.this.spot_instance_id
}

########################################
# Bootstrap provisioning
########################################

resource "null_resource" "bootstrap" {
  depends_on = [aws_spot_instance_request.this]

  provisioner "file" {
    source      = abspath("${path.root}/../.env")
    destination = "/home/${var.ssh_user}/.env"
    connection {
      host        = data.aws_instance.this.public_ip
      user        = var.ssh_user
      private_key = tls_private_key.stack_key.private_key_pem
      type        = "ssh"
    }
  }

  provisioner "file" {
    source      = "${path.module}/bootstrap.sh"
    destination = "/home/${var.ssh_user}/bootstrap.sh"
    connection {
      host        = data.aws_instance.this.public_ip
      user        = var.ssh_user
      private_key = tls_private_key.stack_key.private_key_pem
      type        = "ssh"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 60",
      "chmod +x /home/${var.ssh_user}/bootstrap.sh",
      "sudo -E /home/${var.ssh_user}/bootstrap.sh",
      "echo 'Bootstrap complete. Running devops-setup.sh...' && sleep 5",
      "cd /home/${var.ssh_user}/new-devops-local",
      "chmod +x devops-infra/scripts/devops-setup.sh",
    ]
    connection {
      host        = data.aws_instance.this.public_ip
      user        = var.ssh_user
      private_key = tls_private_key.stack_key.private_key_pem
      type        = "ssh"
    }
  }
}
