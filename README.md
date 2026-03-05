## Project Overview

This project provisions an AWS EKS (Elastic Kubernetes Service) cluster optimized for **GPU workloads** (AI inference and training) with a strong focus on **minimizing GPU cost**.

### What this stack does

- **Runs GPU workloads on-demand**
  - GPU nodes scale **up automatically** when GPU pods are scheduled.
  - GPU nodes scale **down to zero** when idle.
- **Supports optional “pre-warm” hours**
  - Keep 1 GPU node online during **business hours** to avoid 3–6 minute cold-starts.
- **Implements everything as code**
  - EKS, node groups, autoscaling, and schedules are **fully managed via Terraform**.

### High-level architecture

- **EKS cluster**
  - Managed Kubernetes control plane on AWS.
- **Node groups**
  - **CPU node group (always on)**
    - Runs system pods, ingress, and non-GPU workloads.
    - Small, cost-efficient general-purpose instances.
  - **GPU node group (on-demand)**
    - Runs AI inference and training workloads.
    - Scales between **0 and N** nodes based on GPU demand.
- **Autoscaling**
  - **Kubernetes Cluster Autoscaler**
    - Watches for pending pods that request GPUs (e.g. `nvidia.com/gpu: 1`).
    - Scales the GPU node group up/down automatically.
  - **Scheduled scaling (optional)**
    - CloudWatch rules + Lambda / API calls adjust GPU node group desired capacity:
      - Morning: set desired GPUs to `1` (pre-warm).
      - Evening: set desired GPUs back to `0`.

### How GPU workloads behave

- GPU workloads must **explicitly request GPUs** in their pod spec, for example:

  ```yaml
  resources:
    limits:
      nvidia.com/gpu: 1
  ```

- This:
  - Tells Kubernetes the pod needs GPU hardware.
  - Triggers the Cluster Autoscaler to **add GPU nodes if none are available**.

### Desired behavior

- **Idle**
  - CPU nodes: **1**
  - GPU nodes: **0** → **$0 GPU cost**
- **When a GPU job runs**
  - Pod is created with `nvidia.com/gpu` limit.
  - Autoscaler scales GPU node group up.
  - GPU node joins, pod is scheduled.
- **After the job finishes**
  - No GPU pods remain.
  - Autoscaler drains and terminates GPU nodes.
- **With pre-warm enabled**
  - During configured hours, at least **1 GPU node stays online** for instant-start workloads.

### Key outcomes

- **Kubernetes-native GPU autoscaling**
- **Zero GPU cost when idle**
- **Fast startup during working hours (with pre-warm)**
- **Fully reproducible, Terraform-managed infrastructure**

