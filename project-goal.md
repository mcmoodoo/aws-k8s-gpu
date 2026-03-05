## Project Goal

Provision an AWS EKS (Elastic Kubernetes Service) environment that runs GPU workloads for AI inference or training **while minimizing GPU cost**.

## Core Requirements

- **Cost efficiency**
  - GPU instances are expensive and should not run idle.
- **GPU autoscaling**
  - Scale GPU nodes to **zero** when unused.
  - Automatically **start GPU nodes when GPU pods are scheduled**.
- **Optional pre-warm**
  - Optionally **pre-warm GPU nodes during specific hours** (e.g., business hours) to reduce cold-start latency.
- **Infrastructure as Code**
  - Everything is **fully defined in Terraform**.
- **Scaling mechanisms**
  - Use a combination of **Kubernetes autoscaling** and **scheduled scaling**.

---

## Architecture Overview

### Cluster

- **Managed Kubernetes cluster** using **Amazon EKS**.

### Node Groups

- **1️⃣ CPU node group (always running)**
  - **Purpose**
    - System pods
    - Ingress
    - Control / non-GPU workloads
  - **Example instance types**
    - `t3.large`
    - `m6i.large`
  - **Scaling**
    - Min nodes: **1**
    - Max nodes: **3**

- **2️⃣ GPU node group (on-demand)**
  - **Purpose**
    - AI inference
    - Model training
    - Other GPU compute workloads
  - **Example instance types**
    - `g5.xlarge`
    - `g6.xlarge`
  - **Scaling**
    - Min nodes: **0**
    - Max nodes: **3**
    - **Key property**: can **scale to zero** when no GPU pods exist.

---

## Autoscaling Strategy

- **Kubernetes Cluster Autoscaler**
  - Watches for **pending pods**.
  - If a pod requests GPU resources, for example:

    ```yaml
    resources:
      limits:
        nvidia.com/gpu: 1
    ```

    then:

    - Autoscaler **increases the GPU node group size**.
    - AWS **launches a GPU EC2 instance**.
    - Node **joins the cluster**.
    - Pod **gets scheduled**.

  - When GPU pods terminate:
    - Autoscaler **drains the node**.
    - GPU node group **scales down**.
    - GPU instances **terminate**.

- **Result**
  - GPU nodes **automatically scale from 0 → N and back to 0** based on workload.

---

## Scheduled Pre-Warm (Optional)

- **Problem**: Cold GPU startup can take **3–6 minutes**.
- **Goal**: Avoid cold starts during **peak hours** while keeping GPUs off when not needed.

- **Mechanism**
  - Use **Amazon CloudWatch scheduled events** (plus Lambda or direct API calls).

- **Example schedule**

  | Time  | Action                        |
  |-------|-------------------------------|
  | 08:55 | Scale GPU node group to **1** |
  | 18:00 | Scale GPU node group to **0** |

- **Effect**
  - GPUs are **ready during work hours**.
  - GPUs are **off overnight**, minimizing cost.

- **Implementation options**
  - AWS API calls
  - Lambda functions
  - Direct **Auto Scaling group desired capacity** updates

---

## Kubernetes Workload Behavior

- **GPU workloads must request GPUs** explicitly:

  ```yaml
  resources:
    limits:
      nvidia.com/gpu: 1
  ```

- This signals:
  - The Kubernetes scheduler that the pod **requires GPU hardware**.
  - The Cluster Autoscaler to **scale up the GPU node group** if needed.

---

## Terraform Responsibilities

The Terraform project should provision:

- **1️⃣ AWS Infrastructure**
  - VPC
  - Private/public subnets
  - NAT gateway
  - Security groups

- **2️⃣ EKS Cluster**
  - EKS cluster
  - IAM roles
  - Kubernetes networking

- **3️⃣ Node Groups**
  - **CPU node group**
    - Min: **1**
    - Max: **3**
    - Instance type: **general purpose** (e.g., `t3.large`, `m6i.large`)
  - **GPU node group**
    - Min: **0**
    - Max: **3**
    - Instance type: **GPU** (e.g., `g5.xlarge`, `g6.xlarge`)

- **4️⃣ Autoscaler Deployment**
  - Install **Kubernetes Cluster Autoscaler** via Helm.
  - Autoscaler must:
    - Connect to AWS
    - Monitor node groups
    - Scale them dynamically

- **5️⃣ Scheduled Scaling**
  - Create **CloudWatch rules** for scheduled GPU scaling.
  - Example:
    - `08:55` → desired GPU nodes = **1**
    - `18:00` → desired GPU nodes = **0**
  - Backed by:
    - Lambda
    - Or direct autoscaling updates

---

## Desired System Behavior

- **Normal idle state**
  - CPU nodes: **1**
  - GPU nodes: **0** (no cost)

- **When a GPU workload arrives**
  - GPU pod is created.
  - Pod requests `nvidia.com/gpu`.
  - Autoscaler:
    - Detects pending pod.
    - Scales GPU node group **up**.
    - GPU node launches and joins the cluster.
    - Pod is scheduled onto the GPU node.

- **When workload finishes**
  - No GPU pods remain.
  - Autoscaler:
    - Drains GPU node.
    - Terminates GPU instance.
  - GPU cost returns to **$0**.

- **Business hours with pre-warm enabled**
  - CloudWatch event scales GPU node group to **1**.
  - GPU is **ready immediately** for incoming workloads.

---

## Outcome

This architecture provides:

- **Kubernetes-native GPU autoscaling**
- **Cost-efficient GPU usage**
- **Zero GPU cost when idle**
- **Fast startup during work hours (with pre-warm)**
- **Fully reproducible infrastructure using Terraform**
