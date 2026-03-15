# Recipes for LLM GPU EC2 (vLLM / OpenHands LM 7B).
# Run inside aws-vault if needed (e.g.: `aws-vault exec mcmoodoo -- just apply`).

# Literal "{{port}}" for URL patterns (Just would otherwise treat {{port}} as a variable)
_port_literal := "{" + "{" + "port" + "}" + "}"

# --- Default: list commands ---
opt_c := "-c"

list:
	@just --list

# --- Dev environment ---
enter-env:
	aws-vault exec mcmoodoo --duration=4h -- nix develop

# --- Terraform lifecycle ---
plan:
	terraform plan

apply:
	terraform apply

destroy:
	terraform destroy

# --- EC2 SSH helpers ---
ssh:
	ssh ubuntu@$(terraform output -raw openhands_lm_gpu_public_ip)

# --- URLs / quick checks ---
url:
	terraform output -raw openhands_lm_gpu_url

send-request url:
	curl "{{url}}/v1/chat/completions" \
		-H "Content-Type: application/json" \
		-d '{"model":"OpenHands/openhands-lm-7b-v0.1","messages":[{"role":"user","content":"write a short poem about resilience"}],"max_tokens":100}'

ssh-tunnel:
	ssh -L 8000:localhost:8000 \
		-L 35363:localhost:35363 \
		-L 35821:localhost:35821 \
		-L 53805:localhost:53805 \
		-L 56823:localhost:56823 \
		-L 42807:localhost:42807 \
		-L 52255:localhost:52255 \
		ubuntu@$(terraform output -raw openhands_lm_gpu_public_ip)

oh-start llm-base-url:
    docker run -d --rm --pull=always \
        -e AGENT_SERVER_IMAGE_REPOSITORY=ghcr.io/openhands/agent-server \
        -e AGENT_SERVER_IMAGE_TAG=1.12.0-python \
        -e LOG_ALL_EVENTS=true \
        -e SANDBOX_CONTAINER_URL_PATTERN='http://'$(curl ifconfig.me)':{{_port_literal}}' \
        -e DOCKER_HOST_ADDR=$(curl ifconfig.me) \
        -e LLM_BASE_URL={{llm-base-url}} \
        -e LLM_MODEL=openai/OpenHands/openhands-lm-7b-v0.1 \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v ~/.openhands:/.openhands \
        -p 3000:3000 \
        --add-host host.docker.internal:host-gateway \
        --name openhands-app \
        docker.openhands.dev/openhands/openhands:1.5
