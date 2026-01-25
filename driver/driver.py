from __future__ import annotations

import os
import re
import shutil
import subprocess
import json
from dataclasses import dataclass
from pathlib import Path

# -----------------------------
# USER CONFIG: Local Key Paths
# -----------------------------
STACK_KEY_PATH = r"C:\Users\Alex\CloudRift-3-repos\CloudRift-devops\aws-infrastrucutre-terraform\environments\dev\terraform-modules\modules\ec2\keys\stack_key.pem"

# -----------------------------
# Repo URLs + Git creds (loaded from .env)
# -----------------------------
devops_repo_url: str = ""
backend_repo_url: str = ""
frontend_repo_url: str = ""
git_username: str = ""
git_pat: str = ""

# -----------------------------
# Config loaded from .env
# -----------------------------
aws_region: str = ""
aws_access_token: str = ""  # AWS Access Key ID
aws_secret_token: str = ""  # AWS Secret Access Key
aws_session_token: str = ""  # Optionals
account_id: str = ""
owner: str = ""  # Must match IAM username
ec2_dns: str = ""  # NEW: Custom DNS name for EC2
smee_url: str = ""
smee_target: str = ""
smee_backend: str = ""
smee_frontend: str = ""
smee_devops: str = ""
# -----------------------------
# Constants
# -----------------------------
DEFAULT_GIT_BASH = r"C:\Program Files\Git\bin\bash.exe"
ENV_FILE_NAME = ".env"

SETUP_SH = "setup.sh"
DESTROY_SH = "destroy.sh"

# We want Terraform to pick up vars from environments/dev
ENV_DEV_REL = Path("environments") / "dev"
DEV_CREDENTIALS = ENV_DEV_REL / "credentials.auto.tfvars"
DEV_TFVARS = ENV_DEV_REL / "terraform.tfvars"


@dataclass
class RepoPaths:
    devops_repo_root: Path
    infra_dir: Path
    setup_sh: Path
    destroy_sh: Path
    dev_credentials_tfvars: Path
    dev_terraform_tfvars: Path


# ---------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------
def _print_header() -> None:
    print("\nCloudRift Terraform Driver (Windows)")
    print("-" * 70)
    print(f"DEVOPS repo URL:   {devops_repo_url or '<not loaded yet>'}")
    print(f"BACKEND repo URL:  {backend_repo_url or '<not loaded yet>'}")
    print(f"FRONTEND repo URL: {frontend_repo_url or '<not loaded yet>'}")
    print(f"EC2 DNS Name:      {ec2_dns or '<not set>'}")
    print("-" * 70)


def _prompt_yes_no(prompt: str, default_yes: bool = True) -> bool:
    suffix = " [Y/n]: " if default_yes else " [y/N]: "
    while True:
        val = input(prompt + suffix).strip().lower()
        if not val:
            return default_yes
        if val in ("y", "yes"):
            return True
        if val in ("n", "no"):
            return False
        print("Please enter y/yes or n/no.")


def _mask_access_key(k: str) -> str:
    if not k: return "<empty>"
    return ("*" * max(0, len(k) - 4)) + k[-4:]


def _mask_pat(p: str) -> str:
    if not p: return "<empty>"
    return ("*" * max(0, len(p) - 4)) + p[-4:]


# ---------------------------------------------------------------------
# Robust .env parsing
# ---------------------------------------------------------------------
def _strip_inline_comment_preserving_quotes(s: str) -> str:
    in_single = False
    in_double = False
    out: list[str] = []
    for ch in s:
        if ch == "'" and not in_double:
            in_single = not in_single
            out.append(ch)
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            out.append(ch)
            continue
        if ch == "#" and not in_single and not in_double:
            break
        out.append(ch)
    return "".join(out).strip()


def _unquote(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and ((s[0] == s[-1] == '"') or (s[0] == s[-1] == "'")):
        return s[1:-1]
    return s


def _load_env_file(env_path: Path) -> dict[str, str]:
    if not env_path.exists():
        raise FileNotFoundError(f"Missing {ENV_FILE_NAME} next to driver.py: {env_path}")

    data: dict[str, str] = {}
    lines = env_path.read_text(encoding="utf-8", errors="replace").splitlines()
    py_like = re.compile(r"""^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*str\s*=\s*(.+?)\s*$""")

    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"): continue
        if line.lower().startswith("export "): line = line[7:].strip()

        key: str | None = None
        val: str | None = None

        m = py_like.match(line)
        if m:
            key = m.group(1).strip()
            val = m.group(2).strip()
        elif "=" in line:
            k, v = line.split("=", 1)
            key = k.strip()
            val = v.strip()
        else:
            continue

        val = _strip_inline_comment_preserving_quotes(val)
        val = _unquote(val)
        data[key] = val
    return data


def _apply_env(data: dict[str, str]) -> None:
    global aws_region, aws_access_token, aws_secret_token, aws_session_token
    global account_id, owner, ec2_dns
    global devops_repo_url, backend_repo_url, frontend_repo_url
    global git_username, git_pat
    global smee_backend, smee_frontend, smee_devops, smee_url, smee_target

    def pick(*names: str) -> str:
        for n in names:
            if n in data and str(data[n]).strip(): return str(data[n]).strip()
        return ""

    aws_region = pick("AWS_REGION", "aws_region")
    aws_access_token = pick("AWS_ACCESS_TOKEN", "aws_access_token", "AWS_ACCESS", "aws_access")
    aws_secret_token = pick("AWS_SECRET_TOKEN", "aws_secret_token", "AWS_SECRET", "aws_secret")
    aws_session_token = pick("AWS_SESSION_TOKEN", "aws_session_token")
    account_id = pick("ACCOUNT_ID", "account_id")
    owner = pick("OWNER", "owner")
    ec2_dns = pick("ec2_dns")

    devops_repo_url = pick("DEVOPS_REPO_URL", "devops_repo_url")
    backend_repo_url = pick("BACKEND_REPO_URL", "backend_repo_url", "API_REPO_URL", "api_repo_url")
    frontend_repo_url = pick("FRONTEND_REPO_URL", "frontend_repo_url")

    git_username = pick("GITHUB_USER", "GIT_USERNAME", "git_username")
    git_pat = pick("GITHUB_PAT", "GIT_PAT", "git_pat")
    smee_url = pick("SMEE_URL", "smee_url")
    smee_target = pick("SMEE_TARGET", "smee_target")
    smee_backend = pick("SMEE_BACKEND", "smee_backend")
    smee_frontend = pick("SMEE_FRONTEND", "smee_frontend")
    smee_devops = pick("SMEE_DEVOPS", "smee_devops")

    missing = []
    if not aws_region: missing.append("AWS_REGION")
    if not aws_access_token: missing.append("AWS_ACCESS_TOKEN")
    if not aws_secret_token: missing.append("AWS_SECRET_TOKEN")
    if not account_id: missing.append("ACCOUNT_ID")
    if not owner: missing.append("OWNER")
    if not devops_repo_url: missing.append("DEVOPS_REPO_URL")
    if not backend_repo_url: missing.append("BACKEND_REPO_URL")
    if not frontend_repo_url: missing.append("FRONTEND_REPO_URL")

    if missing:
        raise ValueError(f"{ENV_FILE_NAME} is missing required keys: {', '.join(missing)}")


def _print_loaded_env(env_path: Path) -> None:
    print("\nLoaded configuration from .env")
    print("-" * 70)
    print(f"AWS_REGION:        {aws_region}")
    print(f"ACCOUNT_ID:        {account_id}")
    print(f"OWNER:             {owner}")
    print(f"EC2_DNS:           {ec2_dns or '<not set - will use AWS default>'}")
    print("-" * 70)


# ---------------------------------------------------------------------
# Dynamic repo/infra detection
# ---------------------------------------------------------------------
def _find_devops_repo_root_from_script_location(script_dir: Path) -> Path:
    cur = script_dir.resolve()
    for _ in range(20):
        if (cur / ".git").exists(): return cur
        if cur.parent == cur: break
        cur = cur.parent
    raise RuntimeError("Could not locate DevOps repo root (.git).")


def _path_distance(a: Path, b: Path) -> int:
    a_parts = a.parts
    b_parts = b.parts
    common = 0
    for ap, bp in zip(a_parts, b_parts):
        if ap == bp:
            common += 1
        else:
            break
    return (len(a_parts) - common) + (len(b_parts) - common)


def _find_infra_dir(devops_repo_root: Path) -> tuple[Path, Path, Path]:
    setup_candidates = list(devops_repo_root.rglob(SETUP_SH))
    destroy_candidates = list(devops_repo_root.rglob(DESTROY_SH))

    def valid(p: Path) -> bool:
        parts = {x.lower() for x in p.parts}
        return ".git" not in parts and ".terraform" not in parts and "node_modules" not in parts

    setup_candidates = [p for p in setup_candidates if valid(p)]
    destroy_candidates = [p for p in destroy_candidates if valid(p)]

    if not setup_candidates: raise FileNotFoundError(f"Could not find {SETUP_SH}")
    if not destroy_candidates: raise FileNotFoundError(f"Could not find {DESTROY_SH}")

    setup_dirs = {p.parent.resolve(): p.resolve() for p in setup_candidates}
    destroy_dirs = {p.parent.resolve(): p.resolve() for p in destroy_candidates}
    common = set(setup_dirs.keys()) & set(destroy_dirs.keys())

    if common:
        infra = sorted(common, key=lambda x: len(str(x)))[0]
        return infra, setup_dirs[infra], destroy_dirs[infra]

    setup_sh = sorted(setup_candidates, key=lambda x: len(str(x)))[0].resolve()
    infra = setup_sh.parent.resolve()
    destroy_sh = min(destroy_candidates, key=lambda x: _path_distance(infra, x.parent.resolve())).resolve()
    return infra, setup_sh, destroy_sh


def _build_repo_paths(devops_repo_root: Path) -> RepoPaths:
    infra_dir, setup_sh, destroy_sh = _find_infra_dir(devops_repo_root)
    return RepoPaths(
        devops_repo_root=devops_repo_root,
        infra_dir=infra_dir,
        setup_sh=setup_sh,
        destroy_sh=destroy_sh,
        dev_credentials_tfvars=infra_dir / DEV_CREDENTIALS,
        dev_terraform_tfvars=infra_dir / DEV_TFVARS,
    )


def _print_detected_paths(p: RepoPaths) -> None:
    print("\nDetected paths")
    print("-" * 70)
    print(f"Infra directory:          {p.infra_dir}")
    print(f"setup.sh:                 {p.setup_sh}")
    print("-" * 70)


# ---------------------------------------------------------------------
# tfvars writing
# ---------------------------------------------------------------------
def _credentials_tfvars_content() -> str:
    lines = [
        f'aws_access_key = "{aws_access_token}"',
        f'aws_secret_key = "{aws_secret_token}"',
        f'region = "{aws_region}"',
        f'account_id = "{account_id}"',
        f'owner = "{owner}"',
        f'devops_repo_url = "{devops_repo_url}"',
        f'backend_repo_url = "{backend_repo_url}"',
        f'frontend_repo_url = "{frontend_repo_url}"',
        f'git_username = "{git_username}"',
        f'git_pat = "{git_pat}"',
    ]
    if aws_session_token: lines.append(f'aws_session_token = "{aws_session_token}"')
    if ec2_dns: lines.append(f'ec2_dns = "{ec2_dns}"')
    return "\n".join(lines) + "\n"


def _write_credentials(p: RepoPaths) -> None:
    p.dev_credentials_tfvars.parent.mkdir(parents=True, exist_ok=True)
    p.dev_credentials_tfvars.write_text(_credentials_tfvars_content(), encoding="utf-8", newline="\n")
    print(f"Wrote: {p.dev_credentials_tfvars}")


# ---------------------------------------------------------------------
# Git Bash execution
# ---------------------------------------------------------------------
def _resolve_bash_path() -> Path:
    candidate = Path(DEFAULT_GIT_BASH)
    if candidate.exists(): return candidate
    which = shutil.which("bash")
    if which: return Path(which)
    raise FileNotFoundError(f"Git Bash not found at {DEFAULT_GIT_BASH}")


def _clean_env_for_subprocess() -> dict[str, str]:
    env = dict(os.environ)
    for k in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_PROFILE", "AWS_DEFAULT_PROFILE"):
        env.pop(k, None)
    env["TF_IN_AUTOMATION"] = "1"
    # Pass vars for TF
    env["TF_VAR_devops_repo_url"] = devops_repo_url
    env["TF_VAR_backend_repo_url"] = backend_repo_url
    env["TF_VAR_frontend_repo_url"] = frontend_repo_url
    env["TF_VAR_git_username"] = git_username
    env["TF_VAR_git_pat"] = git_pat
    if ec2_dns:
        env["TF_VAR_ec2_dns"] = ec2_dns
    # Pass vars for AWS CLI
    env["AWS_ACCESS_KEY_ID"] = aws_access_token
    env["SMEE_URL"] = smee_url
    env["SMEE_BACKEND"] = smee_backend
    env["SMEE_FRONTEND"] = smee_frontend
    env["SMEE_DEVOPS"] = smee_devops
    env["SMEE_TARGET"] = smee_target
    env["AWS_SECRET_ACCESS_KEY"] = aws_secret_token
    if aws_session_token: env["AWS_SESSION_TOKEN"] = aws_session_token
    env["AWS_DEFAULT_REGION"] = aws_region
    return env


def _run_bash_script(bash_path: Path, script_name: str, cwd: Path, auto_confirm: bool,
                     extra_env: dict[str, str] | None = None) -> None:
    script_path = cwd / script_name
    if not script_path.exists(): raise FileNotFoundError(f"Script not found: {script_path}")

    cmd = [str(bash_path), "-lc", f"sed -i 's/\\r$//' {script_name}; bash {script_name}"]
    stdin_payload = ("yes\n" * 200) if auto_confirm else None

    print(f"\nExecuting in: {cwd}")
    env = _clean_env_for_subprocess()
    if extra_env: env.update(extra_env)

    result = subprocess.run(cmd, cwd=str(cwd), text=True, env=env, input=stdin_payload)
    if result.returncode != 0:
        raise RuntimeError(f"{script_name} failed with exit code {result.returncode}")


# ---------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------
def _preflight_aws_identity(bash_path: Path, cwd: Path) -> None:
    cmd = [str(bash_path), "-lc", "aws sts get-caller-identity || echo 'AWS CLI check failed'"]
    env = _clean_env_for_subprocess()
    subprocess.run(cmd, cwd=str(cwd), text=True, env=env, check=False)


# ---------------------------------------------------------------------
# EC2 Management Functions
# ---------------------------------------------------------------------
def _get_instance_id() -> str | None:
    """Get the instance ID for the current owner's EC2 instance."""
    cmd = [
        "aws", "ec2", "describe-instances",
        "--filters", f"Name=tag:Owner,Values={owner}",
        "--query", "Reservations[0].Instances[0].InstanceId",
        "--output", "text"
    ]

    env = _clean_env_for_subprocess()

    try:
        if not shutil.which("aws"):
            print("⚠ 'aws' command not found on PATH.")
            return None

        result = subprocess.run(cmd, capture_output=True, text=True, env=env)

        if result.returncode != 0 or not result.stdout.strip():
            return None

        instance_id = result.stdout.strip()
        if instance_id == "None":
            return None

        return instance_id
    except Exception:
        return None


def _get_connection_info() -> tuple[str | None, str | None]:
    """
    Fetch EC2 instance IP and DNS.
    Returns: (public_ip, public_dns)
    """
    cmd_ip = [
        "aws", "ec2", "describe-instances",
        "--filters", f"Name=tag:Owner,Values={owner}", "Name=instance-state-name,Values=running",
        "--query", "Reservations[0].Instances[0].PublicIpAddress",
        "--output", "text"
    ]

    cmd_dns = [
        "aws", "ec2", "describe-instances",
        "--filters", f"Name=tag:Owner,Values={owner}", "Name=instance-state-name,Values=running",
        "--query", "Reservations[0].Instances[0].PublicDnsName",
        "--output", "text"
    ]

    env = _clean_env_for_subprocess()

    try:
        if not shutil.which("aws"):
            print("⚠ 'aws' command not found on PATH. Cannot fetch connection info.")
            return None, None

        ip_result = subprocess.run(cmd_ip, capture_output=True, text=True, env=env)
        dns_result = subprocess.run(cmd_dns, capture_output=True, text=True, env=env)

        ip = ip_result.stdout.strip() if ip_result.returncode == 0 else None
        dns = dns_result.stdout.strip() if dns_result.returncode == 0 else None

        if ip == "None": ip = None
        if dns == "None": dns = None

        return ip, dns

    except Exception as e:
        print(f"⚠ Error fetching connection info: {e}")
        return None, None

def _print_jenkins_initial_admin_password(endpoint: str) -> None:
    """
    Fetch and print Jenkins initial admin password (if setup wizard is enabled).
    This works only on a fresh Jenkins with the unlock screen.
    """
    print("\n[Jenkins] Checking for initial admin password...")

    ssh_cmd = [
        "ssh",
        "-o", "StrictHostKeyChecking=no",
        "-i", STACK_KEY_PATH,
        f"ubuntu@{endpoint}",
        "sudo test -f /var/lib/jenkins/secrets/initialAdminPassword "
        "&& sudo cat /var/lib/jenkins/secrets/initialAdminPassword "
        "|| echo '__NO_PASSWORD__'"
    ]

    try:
        result = subprocess.run(
            ssh_cmd,
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            print("⚠ Could not fetch Jenkins password (SSH error)")
            return

        output = result.stdout.strip()

        if output == "__NO_PASSWORD__":
            print("✓ Jenkins setup wizard is disabled (no initial admin password).")
            print("  Admin user is expected to be provisioned via Groovy / JCasC.")
        elif output:
            print("\n" + "=" * 70)
            print("        JENKINS INITIAL ADMIN PASSWORD")
            print("=" * 70)
            print(output)
            print("=" * 70)
            print("Use this password on the Jenkins Unlock screen.")
        else:
            print("⚠ Jenkins password file empty or unreadable.")

    except subprocess.TimeoutExpired:
        print("⚠ Timeout while trying to fetch Jenkins password.")


def _print_connection_info() -> None:
    """Print connection information after deployment."""
    print("\n[Summary] Fetching instance details from AWS...")

    ip, dns = _get_connection_info()

    if not ip and not dns:
        print("⚠ Could not fetch IP/DNS. Is the instance running?")
        return

    print("\n" + "=" * 70)
    print("                 DEPLOYMENT COMPLETE")
    print("=" * 70)

    if ip:
        print(f"\nPublic IP:        {ip}")
    if dns:
        print(f"Public DNS:       {dns}")

    print("-" * 70)

    # Use DNS if available, otherwise IP
    endpoint = dns if dns else ip
    if endpoint:
        print(f"Frontend URL:     http://{endpoint}/")
        print("Jenkins access:")
        print("  SSH tunnel required:")
        print(f"  ssh -i {STACK_KEY_PATH} -L 8080:localhost:8080 ubuntu@{endpoint}")
        print("  Then open: http://localhost:8080")
        print(f"API URL:          http://{endpoint}/api/")
        print("-" * 70)
        print("SSH Connection Command:")
        print(f'ssh -i {STACK_KEY_PATH} ubuntu@{endpoint}')
        print("-" * 70 + "\n")


def _restart_ec2() -> None:
    """Restart the EC2 instance."""
    instance_id = _get_instance_id()

    if not instance_id:
        print("⚠ No instance found for owner: " + owner)
        return

    print(f"\nRestarting EC2 instance: {instance_id}")

    if not _prompt_yes_no("Are you sure you want to restart the instance?", default_yes=False):
        print("Restart cancelled.")
        return

    cmd = ["aws", "ec2", "reboot-instances", "--instance-ids", instance_id]
    env = _clean_env_for_subprocess()

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, env=env)

        if result.returncode == 0:
            print(f"✓ Instance {instance_id} restart initiated successfully")
            print("Note: It may take 1-2 minutes for the instance to restart")
            print("      and services to come back online.")
        else:
            print(f"✗ Failed to restart instance: {result.stderr}")
    except Exception as e:
        print(f"✗ Error restarting instance: {e}")

def _stop_start_ec2() -> None:
    """
    Stop and then start the EC2 instance.

    WARNING:
    - If you are NOT using an Elastic IP, AWS typically assigns a NEW public IPv4 on start.
    - Public DNS will change with the new public IP.
    """
    instance_id = _get_instance_id()
    if not instance_id:
        print("⚠ No instance found for owner: " + owner)
        return

    print("\n" + "=" * 70)
    print("                 STOP + START EC2")
    print("=" * 70)
    print("WARNING: This will likely assign a NEW public IP when the instance starts.")
    print("         If you rely on the old IP/DNS, it will break.")
    print("-" * 70)

    if not _prompt_yes_no("Are you sure you want to STOP and START the instance?", default_yes=False):
        print("Stop/Start cancelled.")
        return

    env = _clean_env_for_subprocess()

    # Stop
    print(f"\nStopping EC2 instance: {instance_id}")
    stop_cmd = ["aws", "ec2", "stop-instances", "--instance-ids", instance_id]
    stop_res = subprocess.run(stop_cmd, capture_output=True, text=True, env=env)
    if stop_res.returncode != 0:
        print(f"✗ Failed to stop instance: {stop_res.stderr}")
        return

    print("✓ Stop initiated. Waiting until instance is stopped...")
    wait_stop_cmd = ["aws", "ec2", "wait", "instance-stopped", "--instance-ids", instance_id]
    wait_stop_res = subprocess.run(wait_stop_cmd, capture_output=True, text=True, env=env)
    if wait_stop_res.returncode != 0:
        print(f"✗ Error while waiting for stop: {wait_stop_res.stderr}")
        return

    # Start
    print(f"\nStarting EC2 instance: {instance_id}")
    start_cmd = ["aws", "ec2", "start-instances", "--instance-ids", instance_id]
    start_res = subprocess.run(start_cmd, capture_output=True, text=True, env=env)
    if start_res.returncode != 0:
        print(f"✗ Failed to start instance: {start_res.stderr}")
        return

    print("✓ Start initiated. Waiting until instance is running...")
    wait_run_cmd = ["aws", "ec2", "wait", "instance-running", "--instance-ids", instance_id]
    wait_run_res = subprocess.run(wait_run_cmd, capture_output=True, text=True, env=env)
    if wait_run_res.returncode != 0:
        print(f"✗ Error while waiting for running: {wait_run_res.stderr}")
        return

    print("\n✓ Instance is running again.")
    print("Reminder: Public IP/DNS may have changed. Fetching updated connection info...\n")
    _show_connection_info()

def _show_connection_info() -> None:
    """Display current EC2 connection information + Jenkins SSH tunnel command."""
    print("\n[Fetching EC2 Connection Info...]")

    ip, dns = _get_connection_info()

    if not ip and not dns:
        print("⚠ No running instance found for owner: " + owner)
        return

    endpoint = dns if dns else ip

    print("\n" + "=" * 70)
    print("                 EC2 CONNECTION INFO")
    print("=" * 70)

    if ip:
        print(f"\nPublic IP:        {ip}")
    if dns:
        print(f"Public DNS:       {dns}")

    print("-" * 70)

    if endpoint:
        print(f"Frontend URL:     http://{endpoint}/")
        print(f"API URL:          http://{endpoint}/api/")
        print("-" * 70)

        print("Jenkins access (via SSH tunnel):")
        print(f"  ssh -i {STACK_KEY_PATH} -L 8080:localhost:8080 ubuntu@{endpoint}")
        print("  Then open: http://localhost:8080")
        print("-" * 70)

        print("Direct SSH connection:")
        print(f"  ssh -i {STACK_KEY_PATH} ubuntu@{endpoint}")

    print("-" * 70 + "\n")
3


# ---------------------------------------------------------------------
# Flows
# ---------------------------------------------------------------------
def _provision(p: RepoPaths, bash_path: Path) -> None:
    print("\n[Provision] Writing tfvars and running setup.sh...")
    _preflight_aws_identity(bash_path, p.infra_dir)
    _write_credentials(p)
    print("Auto-start service (systemd) is ENABLED by default.")
    extra_env = {"ENABLE_AUTOSTART": "1"}
    _run_bash_script(bash_path, SETUP_SH, p.infra_dir, auto_confirm=False, extra_env=extra_env)
    _print_connection_info()
    ip, dns = _get_connection_info()
    endpoint = dns if dns else ip
    if endpoint:
        _print_jenkins_initial_admin_password(endpoint)
    print("[Provision] Completed successfully.")



def _destroy(p: RepoPaths, bash_path: Path) -> None:
    print("\n[Destroy] Writing tfvars and running destroy.sh...")
    _preflight_aws_identity(bash_path, p.infra_dir)
    _write_credentials(p)
    enable_autostart = os.environ.get("ENABLE_AUTOSTART", "0").strip()
    extra_env = {"ENABLE_AUTOSTART": enable_autostart}
    _run_bash_script(bash_path, DESTROY_SH, p.infra_dir, auto_confirm=True, extra_env=extra_env)
    print("[Destroy] Completed successfully.")


# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------
def main() -> int:
    _print_header()
    script_dir = Path(__file__).resolve().parent
    env_path = script_dir / ENV_FILE_NAME

    try:
        env_data = _load_env_file(env_path)
        _apply_env(env_data)
        _print_loaded_env(env_path)
    except Exception as e:
        print(f"ERROR loading .env: {e}")
        return 1

    try:
        devops_root = _find_devops_repo_root_from_script_location(script_dir)
        paths = _build_repo_paths(devops_root)
        _print_detected_paths(paths)
    except Exception as e:
        print(f"ERROR locating repo/infra: {e}")
        return 1

    try:
        bash_path = _resolve_bash_path()
        print(f"\nUsing Git Bash: {bash_path}")
    except Exception as e:
        print(f"ERROR locating Git Bash: {e}")
        return 1

    while True:
        print("\nMenu")
        print("1) Create / Provision infrastructure (setup.sh)")
        print("2) Restart EC2 instance (reboot)")
        print("3) Get DNS and IP information")
        print("4) Stop + Start EC2 instance (WARNING: new public IP likely)")
        print("5) Destroy infrastructure (destroy.sh)")
        print("0) Exit")

        choice = input("> ").strip()

        try:
            if choice == "1":
                _provision(paths, bash_path)
            elif choice == "2":
                _restart_ec2()
            elif choice == "3":
                _show_connection_info()
            elif choice == "4":
                _stop_start_ec2()
            elif choice == "5":
                _destroy(paths, bash_path)

            elif choice == "0":
                print("Exiting.")
                return 0
            else:
                print("Invalid selection.")
        except Exception as e:
            print(f"\nERROR: {e}")
            if not _prompt_yes_no("Return to menu?", default_yes=True):
                return 1


if __name__ == "__main__":
    raise SystemExit(main())