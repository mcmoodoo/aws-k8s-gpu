## OpenHands Web UI WebSocket Issue (EC2)

- **Symptom**: The OpenHands Web UI stays stuck in the **“starting”** state when opening a new conversation, even though the backend containers on EC2 are healthy and logs show no obvious errors.
- **Browser console**: Shows repeated WebSocket failures to URLs like:

  `WebSocket connection to 'ws://localhost:<random_port>/sockets/events/<session_id>?resend_all=true&session_api_key=...' failed`

- **Root cause**: Older OpenHands images (e.g. `docker.openhands.dev/openhands/openhands:1.4`), when accessed from a remote browser, default to using **`localhost`** for the event/WebSocket host. In our EC2 deployment, this makes the browser try to connect back to **its own localhost**, not the EC2 instance, so all WebSocket connections fail and the UI never progresses beyond “starting”.
- **Fix in this project**:
  - The EC2 instance discovers its own **public IPv4** via the EC2 metadata service at boot.
  - That IP is passed into the OpenHands container as `DOCKER_HOST_ADDR`, and `SANDBOX_RUNTIME_BINDING_ADDRESS` is set to `0.0.0.0`.
  - This makes the Web UI generate WebSocket URLs pointing at the **EC2 public IP**, so WebSocket connections succeed and the UI can leave the “starting” state.

