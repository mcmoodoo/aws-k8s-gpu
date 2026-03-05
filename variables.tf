variable "aws_region" {
  description = "AWS region to deploy the EKS cluster into."
  type        = string
  default     = "us-west-2"
}

variable "project_prefix" {
  description = "Prefix used for naming and tagging AWS resources."
  type        = string
  default     = "agentic-gpu"
}

