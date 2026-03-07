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

# --- GPU pre-warm (Step 8) ---
variable "enable_gpu_prewarm" {
  description = "Enable scheduled GPU pre-warm (EventBridge + Lambda). Disabled by default."
  type        = bool
  default     = false
}

variable "gpuprewarm_desired_capacity" {
  description = "Desired GPU node count during pre-warm window (must be <= node group max)."
  type        = number
  default     = 1
}

