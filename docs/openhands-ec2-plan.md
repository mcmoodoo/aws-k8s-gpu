# OpenHands EC2 Implementation Plan (Finalized)

Single EC2 instance running OpenHands (Local GUI + REST API), managed by Terraform. No Kubernetes.

---

## Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | **Port / HTTPS** | Port **8000**, HTTP only. Security group allows **22** (SSH) and **8000**. |
| 2 | **OpenHands component** | **Local GUI + REST API** (API + UI). One process on `0.0.0.0:8000`. |
| 3 | **SSH key** | **Existing key.** Variable = AWS key pair name (the one for `~/.ssh/id_ed25519`). Outputs assume private key at `~/.ssh/id_ed25519`. |
| 4 | **Elastic IP** | **Yes.** EIP attached to the instance so IP and URLs are stable. |

---

## Terraform Deliverables

- **main.tf** – AWS provider (us-east-1), security group (22, 8000), Ubuntu 22.04 EC2 (e.g. m6i.xlarge), Elastic IP, user_data to:
  - Update system, install Docker, Python 3.11 + venv
  - Install OpenHands (Local GUI)
  - Create workspace directory (e.g. `~/openhands-workspaces`)
  - **systemd** unit to start OpenHands server on boot (bind `0.0.0.0`, port 8000, workspace dir, no auth)
- **variables.tf** – `region` (default us-east-1), `instance_type` (default m6i.xlarge), `ssh_key_name` (existing AWS key pair name)
- **outputs.tf** – `public_ip` (EIP), `ssh_command`, `openhands_url` (e.g. `http://<public_ip>:8000`)

---

## OpenHands Server

- **Bind:** `0.0.0.0`
- **Port:** `8000`
- **Workspace:** `~/openhands-workspaces` (or equivalent for the run user)
- **Auth:** None (fully open)
- **Startup:** systemd service, start on boot, restart on failure

Exact install and run command to follow OpenHands “Local GUI” documentation.
