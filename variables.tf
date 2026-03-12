variable "aws_region" {
  description = "AWS region for the OpenHands EC2 instance."
  type        = string
  default     = "us-west-2"
}

variable "instance_type" {
  description = "EC2 instance type for the OpenHands server."
  type        = string
  default     = "m6i.xlarge"
}

variable "gpu_instance_type" {
  description = "EC2 instance type for the OpenHands LM 7B GPU server."
  type        = string
  default     = "g5.4xlarge"
}
variable "ssh_public_key_path" {
  description = "Path to the SSH public key file (e.g. expand with $HOME: -var ssh_public_key_path=$HOME/.ssh/id_ed25519.pub). Terraform creates an EC2 key pair from this."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
