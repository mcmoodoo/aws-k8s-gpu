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
    - Cluster name and Kubernetes version.
- **IAM roles**
  - Create IAM roles for:
    - EKS cluster
    - Node groups (CPU and GPU)
    - Cluster Autoscaler (IRSA role recommended)
- **Outputs**
  - Export cluster name, region, and kubeconfig data so they can be used by `kubectl` and Helm.

### 4. Define Node Groups (Terraform)

- **CPU node group (always-on)**
  - Instance type: general-purpose (e.g., `t3.large`, `m6i.large`).
  - Desired/min/max size: `desired = 1`, `min = 1`, `max = 3`.
  - Attach appropriate IAM role and security groups.

- **GPU node group (on-demand)**
  - Instance type: GPU (e.g., `g5.xlarge`, `g6.xlarge`).
  - Desired/min/max size: `desired = 0`, `min = 0`, `max = 3`.
  - Attach appropriate IAM role and security groups.
  - Ensure node labels / taints (if used) are defined for GPU workloads.

### 5. Configure kubectl Access

- **Generate kubeconfig**
  - Use `aws eks update-kubeconfig` (or Terraform outputs) to create a kubeconfig pointing to the new EKS cluster.
- **Verify connectivity**
  - Run `kubectl get nodes` and `kubectl get pods -A` to confirm the cluster and CPU node group are healthy.

### 6. Install NVIDIA GPU Support (on GPU Nodes)

- **NVIDIA device plugin**
  - Install the NVIDIA Kubernetes device plugin (e.g., via Helm chart or manifest) so pods can request `nvidia.com/gpu`.
- **AMI / driver support**
  - Ensure the GPU node group uses an EKS-optimized GPU AMI or a custom AMI with NVIDIA drivers installed.

### 7. Deploy Kubernetes Cluster Autoscaler

- **IAM + IRSA**
  - Create an IAM policy granting the autoscaler permissions to:
    - Describe and modify node groups / Auto Scaling groups.
  - Bind this policy to a Kubernetes service account via IRSA (IAM Roles for Service Accounts).
- **Helm deployment**
  - Deploy Cluster Autoscaler with Helm (or manifests), configured for:
    - The EKS cluster name.
    - The GPU and CPU node groups.
    - Proper AWS cloud provider flags.
- **Validation**
  - Confirm autoscaler pod is running and healthy.

### 8. Implement Scheduled GPU Pre-Warm (Optional)

- **CloudWatch rules**
  - Create CloudWatch EventBridge / schedule rules:
    - Morning rule: set GPU node group desired capacity to `1`.
    - Evening rule: set GPU node group desired capacity back to `0`.
- **Execution target**
  - Implement one of:
    - Lambda function that calls:
      - `UpdateNodegroupConfig` (EKS) or
      - `UpdateAutoScalingGroup` (ASG).
    - Direct EventBridge rule → AWS Systems Manager / other automation that adjusts node group desired capacity.
- **Parameterization**
  - Make schedule times configurable (e.g., environment variables or Terraform variables).

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

- **User-facing docs**
  - Document:
    - How to deploy GPU workloads (including resource limits).
    - How to enable / disable pre-warm scheduling.
    - How to adjust node group sizes and instance types.
- **Operational runbook**
  - Add notes for:
    - Common failure modes (e.g., autoscaler misconfig, insufficient IAM).
    - How to troubleshoot GPU nodes not appearing or pods stuck in `Pending`.
    - Cost-control checks (ensuring GPU nodes return to 0 when idle).

