# OpenHands on a single EC2 instance (see docs/openhands-ec2-plan.md).
# Requires: variables for region, instance_type, ssh_public_key_path.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Latest Ubuntu 22.04 LTS AMI (us-east-1)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# EC2 key pair from local public key (SSH access)
resource "aws_key_pair" "openhands" {
  key_name   = "openhands-ec2"
  public_key = file(var.ssh_public_key_path)
}

# Security group: SSH (22) and OpenHands API (8000) from anywhere
resource "aws_security_group" "openhands" {
  name        = "openhands-ec2"
  description = "SSH and OpenHands Local GUI (port 8000)"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }
  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "OpenHands GUI + API"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }
}

# User data: install Docker, create dirs, run OpenHands container (port 8000 on host)
locals {
  user_data = <<-EOT
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# System update
apt-get update && apt-get upgrade -y

# Install Docker (Ubuntu 22.04)
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker && systemctl start docker
usermod -aG docker ubuntu

# OpenHands state and workspace dirs (ubuntu user)
mkdir -p /home/ubuntu/.openhands /home/ubuntu/openhands-workspaces
chown -R ubuntu:ubuntu /home/ubuntu/.openhands /home/ubuntu/openhands-workspaces

# Run OpenHands Local GUI (container listens on 3000; we map host 8000 -> 3000)
docker run -d \
  --restart unless-stopped \
  --name openhands-app \
  -p 8000:3000 \
  -e AGENT_SERVER_IMAGE_REPOSITORY=ghcr.io/openhands/agent-server \
  -e AGENT_SERVER_IMAGE_TAG=1.11.4-python \
  -e LOG_ALL_EVENTS=true \
  -v /home/ubuntu/.openhands:/.openhands \
  -v /home/ubuntu/openhands-workspaces:/workspace \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --add-host host.docker.internal:host-gateway \
  docker.openhands.dev/openhands/openhands:1.4
EOT
}

# EC2 instance
resource "aws_instance" "openhands" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.openhands.key_name
  vpc_security_group_ids = [aws_security_group.openhands.id]
  user_data              = local.user_data

  tags = {
    Name = "openhands-ec2"
  }
}

# Elastic IP so the public IP and URLs stay fixed across reboots
resource "aws_eip" "openhands" {
  instance = aws_instance.openhands.id
  domain   = "vpc"
  tags = {
    Name = "openhands-ec2"
  }
}
