# Recipes for EKS GPU cluster.
# Run just inside aws-vault (e.g. aws-vault exec mcmoodoo -- just apply). kubectl/helm use ambient auth.

# --- Default: list commands ---
opt_c := "-c"
[default]
list:
	sh {{ opt_c }} "just --list"

enter-env:
	aws-vault exec mcmoodoo -- nix develop

apply-prewarm:
	terraform apply -var="enable_gpu_prewarm=true"

destroy:
	terraform destroy

# --- Kubeconfig ---
kubeconfig:
	aws eks update-kubeconfig --name agentic-gpu-eks --region us-west-2

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

pods-autoscaler:
	kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler
