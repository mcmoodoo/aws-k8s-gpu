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

# Latest Ubuntu 22.04 LTS AMI (us-west-2)
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

# EC2 instance (user_data from separate script for clarity)
resource "aws_instance" "openhands" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.openhands.key_name
  vpc_security_group_ids = [aws_security_group.openhands.id]
  user_data              = file("${path.module}/scripts/user-data.sh")

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
