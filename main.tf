# LLM GPU EC2 instance (vLLM / OpenHands LM 7B). Single instance, no CPU OpenHands GUI.
# Requires: variables for region, gpu_instance_type, ssh_public_key_path.

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

# Single public subnet in an AZ that supports g5.4xlarge (us-west-2a; 2b/2c also work).
resource "aws_subnet" "openhands_public" {
  vpc_id                  = aws_vpc.openhands.id
  cidr_block              = "10.42.0.0/24"
  availability_zone       = "${var.aws_region}a"
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
  key_name   = "openhands-lm-gpu"
  public_key = file(var.ssh_public_key_path)
}

# Security group: SSH (22) and vLLM API (8000) from anywhere
resource "aws_security_group" "openhands" {
  name        = "openhands-lm-gpu"
  description = "SSH and vLLM OpenAI-compatible API (port 8000)"
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
    description = "vLLM API"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
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

# Elastic IP so the public IP and URLs stay fixed across reboots
resource "aws_eip" "openhands_lm_gpu" {
  instance = aws_instance.openhands_lm_gpu.id
  domain   = "vpc"
  tags = {
    Name = "openhands-lm-gpu"
  }
}
