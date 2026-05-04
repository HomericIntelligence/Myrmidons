# Self-Hosted Runner Setup

The `Apply Agent Definitions` workflow requires a self-hosted GitHub Actions runner
on the same network as the ProjectAgamemnon instance. GitHub-hosted runners cannot
reach Agamemnon because it listens only on the local network.

## Prerequisites

The runner host must have:

- `bash` ≥ 4.4
- `curl`
- `jq`
- `yq` (go-yq v4, mikefarah/yq) — or use `pixi run` which installs pinned versions
- `git`
- `pixi` — install from [prefix.dev](https://prefix.dev/docs/pixi/installation)

If `pixi` is present, the workflow's `setup-pixi` step installs `jq` and `yq` at
pinned versions from the lock file, so only `bash`, `curl`, `git`, and `pixi` are
strictly required on the host.

## Register the runner

1. Go to **GitHub → Settings → Actions → Runners → New self-hosted runner**.
2. Select **Linux / x64** (or arm64 if applicable).
3. Follow the download and configuration commands shown on that page.

   Suggested labels during `./config.sh`:

   ```
   self-hosted, linux
   ```

   These match the `runs-on: [self-hosted, linux]` selector in `apply.yml`.

4. Install as a systemd service so it survives reboots:

   ```bash
   sudo ./svc.sh install
   sudo ./svc.sh start
   sudo ./svc.sh status
   ```

5. Confirm the runner appears as **Idle** in GitHub → Settings → Actions → Runners
   before pushing to `main`.

## Runner user

Run the runner as a dedicated non-root OS user:

```bash
sudo useradd -m -s /bin/bash actions-runner
sudo su - actions-runner
# then run ./config.sh and ./svc.sh install from within this session
```

Grant the user read access to any directories needed by the workflow (workspace
checkout, pixi cache). No broader system privileges are required.

## GitHub repository settings

### Repository variable (not a secret — URL is not sensitive)

| Setting | Value |
|---------|-------|
| Name | `AGAMEMNON_URL` |
| Value | `http://<agamemnon-host>:8080` |

Set via: **Settings → Secrets and variables → Actions → Variables → New repository variable**

### Repository secrets

| Secret | Description |
|--------|-------------|
| `AGAMEMNON_API_KEY` | Bearer token / API key for Agamemnon authentication |

Set via: **Settings → Secrets and variables → Actions → Secrets → New repository secret**

Or via CLI:

```bash
gh secret set AGAMEMNON_API_KEY
```

### Optional: TLS secrets (if Agamemnon uses HTTPS with a private CA)

| Secret | How to generate |
|--------|----------------|
| `AGAMEMNON_CA_CERT_B64` | `base64 -w0 ca.pem` |
| `AGAMEMNON_CLIENT_CERT_B64` | `base64 -w0 client.pem` (mTLS only) |
| `AGAMEMNON_CLIENT_KEY_B64` | `base64 -w0 client.key` (mTLS only) |

The `Configure TLS` step in `apply.yml` decodes these to temp files and sets
`AGAMEMNON_CA_CERT`, `AGAMEMNON_CLIENT_CERT`, and `AGAMEMNON_CLIENT_KEY` for the
remaining steps. The step is skipped entirely if `AGAMEMNON_CA_CERT_B64` is unset.

## Verification

After registering the runner and setting the repository variable/secrets:

1. Push a no-op change to any file under `agents/` (e.g., add and remove a trailing
   newline) to trigger the workflow.
2. In **GitHub → Actions → Apply Agent Definitions**, confirm:
   - The job is picked up by the self-hosted runner (shown in the run header).
   - `Plan` shows expected diff or "no changes".
   - `Apply` exits 0.
   - `Convergence` reports "no drift detected".
   - `Status` shows all agents at desired state.
   - The snapshots artifact is uploaded.

## Failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Job stays "Queued" indefinitely | Runner offline or no runner registered | Start the runner service; workflow times out after 15 minutes |
| `AGAMEMNON_URL` gate skips the job | Repository variable not set | Add `AGAMEMNON_URL` as a repository variable (not a secret) |
| `curl: Could not resolve host` | Runner cannot reach Agamemnon | Check runner host is on the same network as Agamemnon |
| TLS handshake errors | CA cert not trusted | Set `AGAMEMNON_CA_CERT_B64` secret or set `AGAMEMNON_TLS_VERIFY=false` (dev only) |

## Secret rotation

To rotate `AGAMEMNON_API_KEY`:

```bash
gh secret set AGAMEMNON_API_KEY
```

No code changes required — the workflow reads the secret at runtime.

## Concurrency

The workflow inherits the apply lock (`AIM_LOCK_FILE`, default `.myrmidons.lock`)
relative to the checkout directory. Each workflow run gets a fresh checkout, so
lock files do not persist between runs. If you need to prevent concurrent applies
from multiple pushes, add a `concurrency:` block to `apply.yml`:

```yaml
concurrency:
  group: apply-${{ github.ref }}
  cancel-in-progress: false  # queue rather than cancel, to avoid skipping applies
```
