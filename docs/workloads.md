# GPU workloads

- **Example**: `manifests/gpu-example-deployment.yaml` — minimal Deployment that requests one GPU and runs `nvidia-smi -l 60`. Use it to confirm 0→1 scale-up and scale-down.
- **OpenHands LM 7B**: `manifests/openhands-lm-7b.yaml` — vLLM serving OpenHands/openhands-lm-7b-v0.1 with an OpenAI-compatible API on port 8000. Deploy with `just openhands-apply`; after the pod is Ready, run `just openhands-port-forward` and call `http://localhost:8000/v1/chat/completions` (see manifest comments for a curl example).
- **Your workloads**: Use the same pattern: `resources.limits.nvidia.com/gpu: 1` (or more), plus the toleration for `gpu=true:NoSchedule`. Replace the image with your inference stack (e.g. vLLM, TensorRT-LLM, custom model server).
- **Node placement**: GPU pods run only on nodes with label `node-purpose=gpu` and the GPU taint; the scheduler and autoscaler handle placement when you request `nvidia.com/gpu`.
