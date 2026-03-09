# OpenHands EC2 Implementation Plan (Finalized)

Single EC2 instance running OpenHands (Local GUI + REST API), managed by Terraform. No Kubernetes.

---

## Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | **Port / HTTPS** | Port **8000**, HTTP only. Security group allows **22** (SSH) and **8000**. |
| 2 | **OpenHands component** | **Local GUI + REST API** (API + UI). One process on `0.0.0.0:8000`. |
| 3 | **SSH key** | **Public key path.** Variable = path to SSH public key (e.g. `~/.ssh/id_ed25519.pub`). Terraform creates an `aws_key_pair` from that file; instance uses it. User keeps the private key locally (e.g. `~/.ssh/id_ed25519`) for SSH. |
| 4 | **Elastic IP** | **Yes.** EIP attached to the instance so IP and URLs are stable. |

---

## Terraform Deliverables

- **main.tf** – AWS provider (us-west-2 by default via `aws_region`), security group (22, 8000), **aws_key_pair** (created from `file(var.ssh_public_key_path)`), Ubuntu 22.04 EC2 (e.g. m6i.xlarge), Elastic IP, user_data to:
  - Update system, install Docker, Python 3.11 + venv
  - Install OpenHands (Local GUI)
  - Create workspace directory (e.g. `~/openhands-workspaces`)
  - **systemd** unit to start OpenHands server on boot (bind `0.0.0.0`, port 8000, workspace dir, no auth)
- **variables.tf** – `region` (default us-west-2 via `aws_region`), `instance_type` (default m6i.xlarge), `ssh_public_key_path` (path to SSH public key, e.g. `~/.ssh/id_ed25519.pub`)
- **outputs.tf** – `public_ip` (EIP), `ssh_command`, `openhands_url` (e.g. `http://<public_ip>:8000`)

---

## OpenHands Server

- **Bind:** `0.0.0.0`
- **Port:** `8000`
- **Workspace:** `~/openhands-workspaces` (or equivalent for the run user)
- **Auth:** None (fully open)
- **Startup:** systemd service, start on boot, restart on failure

Exact install and run command to follow OpenHands “Local GUI” documentation.
