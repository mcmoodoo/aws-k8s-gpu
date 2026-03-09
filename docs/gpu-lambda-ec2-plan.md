## 1. Core idea

- **Goal**: On-demand GPU inference with **scale-to-zero** and **cost-efficient** usage.
- **No Kubernetes**, no CloudFormation at runtime.
- **AWS Lambda** orchestrates the **EC2 GPU instance lifecycle**.
- **SQS queue** buffers requests while the GPU instance boots and the model server starts.

---

## 2. Components

| Component             | Role                                                                                                  |
|-----------------------|-------------------------------------------------------------------------------------------------------|
| **Client / API Gateway** | Sends inference requests (HTTP/JSON) into the system.                                                |
| **AWS Lambda**        | Orchestrates GPU instance lifecycle: start if stopped, enqueue request, forward when ready, stop when idle. |
| **SQS Queue**         | Holds requests that arrive while the GPU instance is booting or the model is loading.               |
| **EC2 GPU instance**  | Runs a Docker container hosting the LLM model (e.g. vLLM / llama.cpp / TGI).                         |
| **Docker container**  | Hosts the pre-baked model server and exposes an HTTP API for inference.                             |
| **IAM Role for Lambda** | Grants Lambda permissions for `ec2:StartInstances`, `ec2:StopInstances`, `ec2:DescribeInstances`, and SQS operations. |

---

## 3. Workflow

1. **Client sends request** → API Gateway triggers Lambda.
2. **Lambda checks GPU EC2 status**:
   - **If stopped**:
     - Enqueue the request into **SQS**.
     - Call **`StartInstances`** on the GPU EC2 instance.
   - **If running**:
     - Forward the request immediately to the **model server** on the GPU instance.
3. **SQS queue** holds any additional requests while:
   - The EC2 GPU instance boots (~60–90 seconds),
   - Docker daemon starts and the **model container** starts (~20–30 seconds),
   - The **model weights load** into GPU memory (~10–30 seconds).
4. Once the model server is ready, **Lambda dequeues requests from SQS** and forwards them to the model server HTTP endpoint.
5. An **idle timeout** (implemented via Lambda or an internal watchdog) stops the EC2 instance when no requests have arrived for *X* seconds/minutes:
   - Lambda (or a scheduled Lambda) checks last-activity time.
   - If idle beyond threshold → call **`StopInstances`** on the GPU EC2 instance.

---

## 4. Cost behavior

- **EC2 GPU** is billed **only while running** (stopped instances incur only minimal EBS cost).
- **Spot instances** can be used to reduce GPU cost significantly (with the usual interruption trade-offs).
- **EBS storage** persists the model and container image layers (~\$10–20/month depending on size).
- **SQS and Lambda** costs are negligible for moderate traffic levels compared to GPU time.

---

## 5. Key points

- **Cold start**: Expect **2–3 minutes** from first request to first response (EC2 boot + Docker + model load).
- **Simplicity**: No Kubernetes, no CloudFormation at runtime → simpler operational footprint.
- **Reliability**: SQS ensures requests are **not dropped** while the GPU is booting or the model is warming up.
- **Orchestration**: Lambda owns the full **start/stop + request forwarding** loop for the GPU instance and model server.

