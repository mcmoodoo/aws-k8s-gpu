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
