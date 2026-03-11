output "public_ip" {
  description = "Elastic IP of the OpenHands EC2 instance (stable across reboots)."
  value       = aws_eip.openhands.public_ip
}

output "ssh_command" {
  description = "Example SSH command to connect (assumes private key at ~/.ssh/id_ed25519)."
  value       = "ssh -i ~/.ssh/id_ed25519 ubuntu@${aws_eip.openhands.public_ip}"
}

output "openhands_url" {
  description = "OpenHands Local GUI + API base URL."
  value       = "http://${aws_eip.openhands.public_ip}:8000"
}

output "openhands_lm_gpu_public_ip" {
  description = "Elastic IP of the OpenHands LM 7B GPU EC2 instance."
  value       = aws_eip.openhands_lm_gpu.public_ip
}

output "openhands_lm_gpu_url" {
  description = "OpenHands LM 7B vLLM OpenAI-compatible base URL."
  value       = "http://${aws_eip.openhands_lm_gpu.public_ip}:8000"
}
