# Recipes for EKS GPU cluster.
# Run just inside aws-vault (e.g. aws-vault exec mcmoodoo -- just apply). kubectl/helm use ambient auth.

# --- Default: list commands ---
opt_c := "-c"
[default]
list:
	sh {{ opt_c }} "just --list"

enter-env:
	aws-vault exec mcmoodoo --duration=4h -- nix develop

# --- Terraform ---
plan:
	terraform plan

apply:
	terraform apply

destroy:
	terraform destroy

ssh:
    ssh ubuntu@$(terraform output -raw public_ip)

# --- Kubeconfig ---
kubeconfig:
	aws eks update-kubeconfig --name agentic-gpu-eks --region us-west-2

# --- OpenHands LM 7B (vLLM, OpenAI-compatible API on :8000) ---
openhands-apply:
	kubectl apply -f manifests/openhands-lm-7b.yaml

openhands-delete:
	kubectl delete -f manifests/openhands-lm-7b.yaml

openhands-watch:
	kubectl get pods -n gpu-lab -l app=openhands-lm-7b -w

openhands-port-forward:
	kubectl port-forward -n gpu-lab svc/openhands-lm-7b 8000:8000

# Show external endpoint for OpenHands (after LoadBalancer has EXTERNAL-IP)
openhands-url:
	@kubectl get svc -n gpu-lab openhands-lm-7b -o wide
	@echo "Base URL: http://<EXTERNAL-IP above>:8000"

openhands-logs:
	kubectl logs -n gpu-lab -l app=openhands-lm-7b -f

send-request-lb host:
	curl "http://{{host}}:8000/v1/chat/completions" \
		-H "Content-Type: application/json" \
		-d '{"model":"OpenHands/openhands-lm-7b-v0.1","messages":[{"role":"user","content":"write a poem about resilience"}],"max_tokens":100}'
