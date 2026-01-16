# provider "aws" {
#     region = var.aws_region
# }


resource "aws_instance" "this" {
  ami           = var.ami
  instance_type = var.instance_type
  subnet_id     = var.subnet_id
  key_name      = aws_key_pair.stack_key.key_name
  tags = {
    Name = var.instance_name
  }
  vpc_security_group_ids = [var.security_group_id]

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

}

resource "null_resource" "bootstrap" {
  depends_on = [aws_instance.this]

  # Copy local .env (contains GIT_PAT/USER and repo URLs) to the EC2 host
  provisioner "file" {
    source      = abspath("${path.root}/../.env")
    destination = "/home/${var.ssh_user}/.env"
    connection {
      host        = aws_instance.this.public_ip
      user        = var.ssh_user
      private_key = tls_private_key.stack_key.private_key_pem
      type        = "ssh"
    }
  }

  provisioner "file" {
    source      = "${path.module}/bootstrap.sh"
    destination = "/home/${var.ssh_user}/bootstrap.sh"
    connection {
      host        = aws_instance.this.public_ip
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
      host        = aws_instance.this.public_ip
      user        = var.ssh_user
      private_key = tls_private_key.stack_key.private_key_pem
      type        = "ssh"
    }
  }
}

# Create a new key pair
resource "tls_private_key" "stack_key" {
  algorithm = var.algorithm
  rsa_bits  = var.rsa
}

resource "local_file" "private_key" {
  content = tls_private_key.stack_key.private_key_pem
  #   filename = var.private_filename
  filename = "${path.module}/keys/stack_key.pem"

}

resource "local_file" "public_key" {
  content  = tls_private_key.stack_key.public_key_openssh
  filename = "${path.module}/keys/stack_key.pub"
  #   filename = var.public_filename
}

resource "aws_key_pair" "stack_key" {
  public_key = tls_private_key.stack_key.public_key_openssh
  key_name   = var.key_name
}

