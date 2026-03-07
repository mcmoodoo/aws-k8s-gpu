# Runbook (checklist-style)

Personal checklist for operating the EKS GPU cluster.

---

## Cluster Autoscaler (Step 7)

After Terraform has created node groups and tagged the ASGs:

1. **Apply Terraform** (if not already done):
   ```bash
   aws-vault exec mcmoodoo -- terraform apply
   ```
   If ASGs already exist, a second apply may be needed so the ASG tags are created.

2. **Add Helm repo and install Cluster Autoscaler** (from repo root, inside `nix develop`).  
   Pin the autoscaler image to your cluster’s **Kubernetes minor version** (e.g. EKS 1.31 → `v1.31.0`). Check with `kubectl version --short` (use Server Version):
   ```bash
   helm repo add autoscaler https://kubernetes.github.io/autoscaler
   helm repo update
   helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
     --namespace kube-system \
     --set autoDiscovery.clusterName=agentic-gpu-eks \
     --set awsRegion=us-west-2 \
     --set image.tag=v1.31.0
   ```
   Replace `v1.31.0` with a tag that matches your cluster (e.g. `v1.32.0` for EKS 1.32).

3. **Verify**:
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler
   kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler --tail=30
   ```
   Logs should show "Poll finished" and node group discovery (no errors).

---

## Example GPU workload (Step 9)

- [ ] Apply the example deployment (creates `gpu-lab` namespace and a single GPU pod):
  ```bash
  kubectl apply -f manifests/gpu-example-deployment.yaml
  ```
- [ ] Watch: pod may stay `Pending` until the GPU node group scales 0→1 (~3–6 min). Then:
  ```bash
  kubectl get pods -n gpu-lab -w
  kubectl get nodes -l node-purpose=gpu
  ```
- [ ] To test scale-down: delete the deployment and wait; GPU node should drain and scale to 0.
  ```bash
  kubectl delete -f manifests/gpu-example-deployment.yaml
  ```

## Deploying your own GPU workload

- [ ] Ensure pod requests `nvidia.com/gpu` and tolerates GPU taint:
  ```yaml
  resources:
    limits:
      nvidia.com/gpu: 1
  tolerations:
    - key: "gpu"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"
  ```
- [ ] Deploy to a namespace (e.g. `gpu-lab`); autoscaler will scale GPU node group 0→1 if needed.
- [ ] Check node: `kubectl get nodes -l node-purpose=gpu`

---

## GPU pre-warm (Step 8)

Optional. When enabled, EventBridge runs Lambda at **09:00** and **12:00** America/New_York to set GPU node group desired capacity to 1 and 0.

- [ ] **Enable**: set in `variables.tf` or at apply time:
  ```bash
  aws-vault exec mcmoodoo -- terraform apply -var="enable_gpu_prewarm=true"
  ```
- [ ] **Disable**: `terraform apply -var="enable_gpu_prewarm=false"` (or set default in variables.tf).
- [ ] **Customize**: variable `gpuprewarm_desired_capacity` (default `1`). Schedule is **UTC** in `gpu-prewarm.tf`: 14:00 UTC (09:00 EST) start, 17:00 UTC (12:00 EST) end; edit the cron expressions there for other times or timezones.

---

## Adjusting node group sizes (Terraform)

- [ ] Edit `eks-nodegroups.tf`: change `min_size` / `max_size` / `desired_size` in `scaling_config`.
- [ ] Run `terraform plan` then `terraform apply`.

---

## Verifying autoscaler behavior

- [ ] **CPU**: Scale a CPU-heavy deployment; expect `cpu-system` to grow up to max 3.
- [ ] **GPU**: Deploy a pod with `nvidia.com/gpu: 1`; expect `gpu-inference` 0→1, then node Ready and pod Running.
- [ ] **Scale-down**: Delete GPU workload; after a few minutes GPU node should drain and ASG go to 0.

---

## Troubleshooting

| Symptom | Check |
|--------|--------|
| Pods stuck `Pending` (GPU) | Node group has capacity? `kubectl get nodes -l node-purpose=gpu`. Autoscaler logs: `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-cluster-autoscaler`. |
| Autoscaler in CrashLoopBackOff | Get crash reason: `kubectl logs -n kube-system <pod-name> --previous`. Often caused by **image vs cluster version mismatch**: pin `image.tag` to your K8s minor version (e.g. `--set image.tag=v1.31.0`). Reinstall with matching tag. |
| `nvidia.com/gpu` not visible | NVIDIA device plugin running: `kubectl get pods -n gpu-system`. Only on GPU nodes when they exist. |
| GPU nodes not scaling to 0 | No GPU pods left? `kubectl get pods -A | grep -i gpu`. Autoscaler scale-down delay (~10 min) is normal. |
