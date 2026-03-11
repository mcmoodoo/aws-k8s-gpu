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

# --- Networking: dedicated VPC + public subnet for the EC2 instance ---

resource "aws_vpc" "openhands" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "openhands-vpc"
  }
}

resource "aws_internet_gateway" "openhands" {
  vpc_id = aws_vpc.openhands.id

  tags = {
    Name = "openhands-igw"
  }
}

resource "aws_subnet" "openhands_public" {
  vpc_id                  = aws_vpc.openhands.id
  cidr_block              = "10.42.0.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "openhands-public-subnet"
  }
}

resource "aws_route_table" "openhands_public" {
  vpc_id = aws_vpc.openhands.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.openhands.id
  }

  tags = {
    Name = "openhands-public-rt"
  }
}

resource "aws_route_table_association" "openhands_public" {
  subnet_id      = aws_subnet.openhands_public.id
  route_table_id = aws_route_table.openhands_public.id
}

# Latest Ubuntu 22.04 LTS AMI (CPU instance)
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

# GPU-optimized AMI with NVIDIA drivers preinstalled (AWS Deep Learning Base OSS Nvidia Driver GPU AMI, Ubuntu 22.04)
data "aws_ami" "ubuntu_gpu" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*"]
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

# Security group: SSH (22) and OpenHands API (8000) from anywhere, attached to our VPC
resource "aws_security_group" "openhands" {
  name        = "openhands-ec2"
  description = "SSH and OpenHands Local GUI (port 8000)"
  vpc_id      = aws_vpc.openhands.id

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
  subnet_id              = aws_subnet.openhands_public.id
  vpc_security_group_ids = [aws_security_group.openhands.id]
  user_data              = file("${path.module}/scripts/user-data.sh")

  tags = {
    Name = "openhands-ec2"
  }
}

# GPU EC2 instance running OpenHands LM 7B with vLLM
resource "aws_instance" "openhands_lm_gpu" {
  ami                    = data.aws_ami.ubuntu_gpu.id
  instance_type          = var.gpu_instance_type
  key_name               = aws_key_pair.openhands.key_name
  subnet_id              = aws_subnet.openhands_public.id
  vpc_security_group_ids = [aws_security_group.openhands.id]
  user_data              = file("${path.module}/scripts/user-data-gpu.sh")

  root_block_device {
    volume_size = 300
    volume_type = "gp3"
  }

  tags = {
    Name = "openhands-lm-gpu"
  }
}

resource "aws_eip" "openhands_lm_gpu" {
  instance = aws_instance.openhands_lm_gpu.id
  domain   = "vpc"
  tags = {
    Name = "openhands-lm-gpu"
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
