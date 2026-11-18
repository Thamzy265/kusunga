# Windows CI on the homelab — setup guide

Date: 2026-11-18 — For: the PM — Fixes: the Windows CI job that can't run on GitHub's Windows machines (billing)

The Windows job in `.github/workflows/check.yml` will run on a Windows VM in your homelab, as a GitHub "self-hosted runner". The Mac jobs stay on GitHub's machines.

You do every step here yourself. The registration token in step 5 is a secret: don't paste it into chat or into any file in the repo.

## 1. The VM

- Windows 11 Pro (or Windows Server 2022), 64-bit.
- At least 4 CPU cores, 8 GB memory, 80 GB disk.
- Install all Windows updates and restart.
- Put it on its own network segment (VLAN) if you can: it needs the internet, but not your other machines.
- Take a snapshot when you finish step 6, so you can roll back to a clean runner.

## 2. A user for the runner

Make a local **standard** user (not an administrator), for example `ghrunner`, with a strong password. The runner service will run as this user. Sign in as it once, so Windows makes its profile folder.

## 3. Developer Mode

Settings → System → For developers → **Developer Mode** on. Flutter needs it to build apps that use plugins on Windows. Kusunga uses plugins.

## 4. The tools

Open PowerShell **as administrator** and run:

```powershell
winget install --id Git.Git -e
winget install --id Microsoft.PowerShell -e
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

The last one installs the C++ compiler, the Windows SDK and CMake ("Desktop development with C++"). It takes a while. Restart when it finishes.

You don't need to install Flutter: the workflow downloads Flutter 3.44.6 itself.

## 5. Register the runner

1. On github.com, open **Thamzy265/kusunga → Settings → Actions → Runners → New self-hosted runner**.
2. Choose **Windows**, **x64**. GitHub shows the commands to download the runner and a `config.cmd` line with a one-time token.
3. In an administrator PowerShell, run GitHub's commands in `C:\actions-runner`.
4. When `config.cmd` asks:
   - runner group: press Enter (Default);
   - runner name: `homelab-win` (or anything);
   - **additional labels: `kusunga-windows`** (this is how the workflow finds it);
   - work folder: press Enter (`_work`);
   - **run as a service: `Y`**;
   - **service account: `.\ghrunner`** and its password (not the default Network Service).

## 6. Check it

- On GitHub, **Settings → Actions → Runners** shows `homelab-win` as **Idle**, with the labels `self-hosted`, `Windows`, `X64`, `kusunga-windows`.
- In Windows, Services shows "GitHub Actions Runner (…)" as Running, started automatically.
- Then tell the lead. Take the VM snapshot now.

## 7. Safety settings on GitHub

**Settings → Actions → General:**
- Keep **"Run workflows from fork pull requests"** off. The repo is private, so only you can start jobs; leave it that way. Never make the repo public while this runner is attached. In a public repo anyone could run code on your VM.

## What the team does next

The developer changes one line in `.github/workflows/check.yml`, on a branch:

```yaml
runs-on: [self-hosted, Windows, X64, kusunga-windows]
```

It goes through the normal gates. The first run on your VM is the first time Kusunga's Windows code is compiled and tested.

## Day to day

- The VM must be on for the Windows job to run. If it is off, the job waits in the queue (and fails after 24 hours).
- The runner updates itself.
- Billing: GitHub has announced a small per-minute charge for self-hosted runners on private repos in the past. Check **Settings → Billing** after the first runs.
- To remove it: **Settings → Actions → Runners → homelab-win → Remove**, then run `config.cmd remove` on the VM.
