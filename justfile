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

apply-prewarm:
	terraform apply -var="enable_gpu_prewarm=true"

destroy:
	terraform destroy

# --- Kubeconfig ---
kubeconfig:
	aws eks update-kubeconfig --name agentic-gpu-eks --region us-west-2

# --- Cluster Autoscaler (Step 7). Set image_tag to match EKS minor version, e.g. v1.35.0. Uses IRSA (run tf apply first). ---
install-autoscaler image_tag="v1.35.0":
	helm repo add autoscaler https://kubernetes.github.io/autoscaler
	helm repo update
	helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
		--namespace kube-system \
		--set autoDiscovery.clusterName=agentic-gpu-eks \
		--set awsRegion=us-west-2 \
		--set image.tag={{ image_tag }} \
		--set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform output -raw cluster_autoscaler_role_arn)

# --- NVIDIA device plugin (Step 6). Tolerate gpu=true so the DaemonSet runs on GPU nodes and advertises nvidia.com/gpu. ---
install-nvidia-plugin:
	helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
	helm repo update
	helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin --namespace kube-system \
		--set tolerations[0].key=gpu \
		--set tolerations[0].operator=Equal \
		--set-string tolerations[0].value=true \
		--set tolerations[0].effect=NoSchedule

# --- Example GPU workload (Step 9) ---
gpu-demo-apply:
	kubectl apply -f manifests/gpu-example-deployment.yaml

gpu-demo-delete:
	kubectl delete -f manifests/gpu-example-deployment.yaml

gpu-demo-watch:
	kubectl get pods -n gpu-lab -w

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

# --- Quick checks ---
nodes:
	kubectl get nodes

nodes-gpu:
	kubectl get nodes -l node-purpose=gpu

pods-autoscaler:
	kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler

autoscaler-logs:
	kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=30

send-request-lb host:
	curl "http://{{host}}:8000/v1/chat/completions" \
		-H "Content-Type: application/json" \
		-d '{"model":"OpenHands/openhands-lm-7b-v0.1","messages":[{"role":"user","content":"write a poem about resilience"}],"max_tokens":100}'
