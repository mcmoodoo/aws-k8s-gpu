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

# --- Cluster Autoscaler (Step 7). Set image_tag to match EKS minor version, e.g. v1.31.0 ---
install-autoscaler image_tag="v1.31.0":
	helm repo add autoscaler https://kubernetes.github.io/autoscaler
	helm repo update
	helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
		--namespace kube-system \
		--set autoDiscovery.clusterName=agentic-gpu-eks \
		--set awsRegion=us-west-2 \
		--set image.tag={{ image_tag }}

# --- NVIDIA device plugin (Step 6) ---
install-nvidia-plugin:
	helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
	helm repo update
	helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin --namespace kube-system

# --- Example GPU workload (Step 9) ---
gpu-demo-apply:
	kubectl apply -f manifests/gpu-example-deployment.yaml

gpu-demo-delete:
	kubectl delete -f manifests/gpu-example-deployment.yaml

gpu-demo-watch:
	kubectl get pods -n gpu-lab -w

# --- Quick checks ---
nodes:
	kubectl get nodes

nodes-gpu:
	kubectl get nodes -l node-purpose=gpu

pods-autoscaler:
	kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler

verify-cluster-autoscaler-started:
	kubectl -n kube-system get pods -l "app.kubernetes.io/name=aws-cluster-autoscaler,app.kubernetes.io/instance=cluster-autoscaler"

autoscaler-logs:
	kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=30
