## Implementation Plan

Step-by-step plan to build the AWS EKS GPU cluster with autoscaling and optional pre-warm.

### 1. Prerequisites and Setup

- **AWS account and credentials**
  - Use your existing AWS account with permissions to create VPCs, EKS, EC2, IAM, and CloudWatch resources.
  - Authenticate via `aws-vault`, e.g.:
    - `aws-vault exec mcmoodoo -- terraform plan`
    - `aws-vault exec mcmoodoo -- terraform apply`
- **Tooling**
  - Ensure the following are installed on your local machine:
    - Terraform
    - AWS CLI
    - Nix (for `flake.nix` dev shell)
  - Use the Nix dev shell to get Kubernetes tooling:
    - `nix develop`
    - Inside the dev shell, you have:
      - `kubectl`
      - `helm` (as `kubernetes-helm`)
      - `k9s`
      - `kubectx`
- **Baseline config and naming**
  - **AWS region**: fix to `us-west-2`.
  - **Naming (generic, non-app-specific)**:
    - Project/tag prefix: `agentic-gpu`
    - EKS cluster name: `agentic-gpu-eks`
    - VPC name/tag: `agentic-gpu-vpc`
    - CPU node group name: `cpu-system`
    - GPU node group name: `gpu-inference`
  - **GPU instance type (inference-focused)**:
    - Use `g5.4xlarge` for the GPU node group.
  - **Terraform provider versioning**:
    - Use the AWS provider with version constraint **`>= 6.0`**.

### 2. Define Network Infrastructure (Terraform)

- **VPC**
  - Create a new VPC dedicated to this cluster.
  - CIDR: `10.0.0.0/16`.
- **Availability Zones**
  - Use 2 AZs in `us-west-2` (e.g., `us-west-2a` and `us-west-2b`).
- **Subnets**
  - Create **2 public subnets** (one per AZ) for:
    - EKS node groups (CPU + GPU)
    - Public load balancers.
  - Create **2 private subnets** (one per AZ) reserved for future use (e.g., internal services, databases).
- **Internet connectivity**
  - Attach an Internet Gateway to the VPC.
  - Public subnets:
    - Route directly to the Internet Gateway.
  - Private subnets:
    - Route to a **single shared NAT Gateway** in one public subnet (cost-optimized, dev-friendly).
- **Security groups**
  - Define security groups for:
    - EKS control plane / nodes (allowing only required ports from the internet or specific CIDRs).
    - Ingress / load balancers.
  - Rely on security groups to restrict access to nodes exposed in public subnets; hardening can be iterated later.

### 3. Create the EKS Cluster (Terraform)

- **EKS control plane**
  - Define an EKS cluster resource referencing:
    - The VPC and subnets.
    - Cluster name and Kubernetes version (initially using the **latest EKS-supported version** at creation time).
- **Managed add-ons**
  - Enable EKS-managed add-ons for:
    - `vpc-cni`
    - `coredns`
    - `kube-proxy`
  - Let EKS manage patching and minor updates for these components.
- **IAM roles**
  - Create IAM roles for:
    - EKS cluster
    - Node groups (CPU and GPU).
- **Cluster access (aws-auth)**
  - Map the IAM identity used via `aws-vault exec mcmoodoo` into the `system:masters` group to grant cluster-admin access.
  - Keep additional IAM-to-RBAC mappings minimal initially; expand later as needed.
- **Outputs**
  - Export cluster name, region, and kubeconfig data so they can be used by `kubectl` and Helm.

### 4. Define Node Groups (Terraform)

- **CPU node group (always-on)**
  - Instance type: general-purpose `t3.large`.
  - Desired/min/max size: `desired = 1`, `min = 1`, `max = 3`.
  - Attach appropriate IAM role and security groups.

- **GPU node group (on-demand)**
  - Instance type: GPU `g5.4xlarge`.
  - Desired/min/max size: `desired = 0`, `min = 0`, `max = 1` (strict cost cap, single GPU node).
  - Purchase option: **On-Demand only** (no Spot, to avoid interruptions).
  - Attach appropriate IAM role and security groups.
  - Configure GPU nodes with:
    - Label: `node-purpose=gpu`.
    - Taint: `gpu=true:NoSchedule`, with GPU workloads explicitly tolerating this taint.

### 5. Configure kubectl Access

- **Generate kubeconfig**
  - Use `aws eks update-kubeconfig` (or Terraform outputs) to create a kubeconfig pointing to the new EKS cluster.
- **Verify connectivity**
  - Run `kubectl get nodes` and `kubectl get pods -A` to confirm the cluster and CPU node group are healthy.

### 6. Install NVIDIA GPU Support (on GPU Nodes)

- **AMI / driver support**
  - Configure the GPU node group to use the standard **EKS-optimized accelerated GPU AMI** for `g5` in `us-west-2`.
  - Rely on this AMI to provide NVIDIA drivers (no custom AMI or in-cluster driver management initially).
- **NVIDIA device plugin**
  - Install the NVIDIA Kubernetes device plugin via **Helm** so pods can request `nvidia.com/gpu`.
  - Deploy it into `kube-system` with default settings sufficient to expose GPU resources to the scheduler.
- **Frameworks and runtimes**
  - Do not install extra cluster-wide GPU frameworks.
  - Let individual workload containers bring their own CUDA / ML frameworks as needed.

### 7. Deploy Kubernetes Cluster Autoscaler

- **IAM permissions**
  - Initially, rely on the **node instance profile IAM role** (shared by CPU and GPU node groups) to grant Cluster Autoscaler permissions to:
    - Describe and modify node groups / Auto Scaling groups.
  - Plan a future hardening step to move these permissions into a **dedicated IAM role via IRSA**, attached only to the autoscaler service account.
- **Helm deployment**
  - Deploy Cluster Autoscaler with Helm (or manifests), configured for:
    - The EKS cluster name.
    - The GPU and CPU node groups.
    - Proper AWS cloud provider flags.
- **Validation**
  - Confirm autoscaler pod is running and healthy.

### 8. Implement Scheduled GPU Pre-Warm (Optional)

### 8. Implement Scheduled GPU Pre-Warm (Optional)

- **Feature flag**
  - Implement scheduled GPU pre-warm as an **optional feature**, controlled by a Terraform variable (e.g., `enable_gpu_prewarm`), **disabled by default**.
- **CloudWatch / EventBridge rules**
  - Define EventBridge (CloudWatch) schedule rules in the **`America/New_York` (EST)** timezone:
    - Morning rule (daily): around `09:00` EST → set GPU node group desired capacity to `1`.
    - Noon rule (daily): around `12:00` EST → set GPU node group desired capacity back to `0`.
- **Execution target**
  - Use the simpler **EventBridge → Lambda** pattern:
    - Lambda function calls:
      - `UpdateNodegroupConfig` (EKS) or the underlying Auto Scaling APIs.
    - Lambda adjusts the `gpu-inference` node group desired capacity according to the schedule (1 during pre-warm window, 0 otherwise).
- **Parameterization**
  - Expose variables for:
    - Enabling/disabling pre-warm (`enable_gpu_prewarm`).
    - Pre-warm start and end times.
    - Desired GPU node count during pre-warm (default `1`, consistent with `max = 1`).

### 9. Define Example GPU Workload

- **Sample deployment**
  - Create a simple GPU-enabled workload (e.g., a CUDA or inference demo pod) that requests:

    ```yaml
    resources:
      limits:
        nvidia.com/gpu: 1
    ```

- **Test behavior**
  - Apply the deployment and watch:
    - GPU node group scaling from 0 → 1.
    - Node joining the cluster.
    - Pod transitioning to `Running`.
  - Delete the workload and validate:
    - Autoscaler drains the GPU node.
    - GPU node group scales back to 0.

### 10. Document Usage and Operations

- **Documentation layout**
  - Keep `README.md` focused on:
    - High-level overview.
    - Quickstart instructions (how to bring the cluster up/down).
  - Add a `docs/` folder (e.g., `docs/runbook.md`, `docs/workloads.md`) for deeper operational details.
- **Checklist-style runbook (for personal use)**
  - In `docs/runbook.md`, maintain concise checklists for:
    - Deploying a new GPU workload (including resource limits, labels, tolerations).
    - Enabling / disabling GPU pre-warm and changing its schedule.
    - Adjusting node group sizes and instance types safely via Terraform.
    - Verifying autoscaler behavior for CPU and GPU node groups.
  - Capture common failure modes and quick diagnostics:
    - Autoscaler misconfiguration (pods stuck `Pending`, nodes not scaling).
    - GPU nodes not appearing or `nvidia.com/gpu` not visible.
    - Ensuring GPU nodes return to 0 when idle (cost checks).

