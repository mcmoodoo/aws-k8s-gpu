#!/bin/bash
# GPU EC2 bootstrap for OpenHands LM 7B with vLLM.
# Installs Docker + NVIDIA container toolkit and runs vLLM OpenAI server on port 8000.
set -e
export DEBIAN_FRONTEND=noninteractive

# System update
apt-get update && apt-get upgrade -y

# Install basic tools
apt-get install -y ca-certificates curl gnupg lsb-release

# Install Docker (Ubuntu 22.04)
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi
if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
fi
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker && systemctl start docker
usermod -aG docker ubuntu || true

# On AWS Deep Learning Base GPU AMI the NVIDIA drivers and container toolkit
# are already installed and configured, so we only need to start the vLLM container.

# Pull and run vLLM OpenAI-compatible server for OpenHands LM 7B
docker run -d \
  --name openhands-lm-7b \
  --restart unless-stopped \
  --gpus all \
  -p 8000:8000 \
  vllm/vllm-openai:latest \
  --model OpenHands/openhands-lm-7b-v0.1 \
  --max-model-len 8192 \
  --host 0.0.0.0 \
  --trust-remote-code

