from __future__ import annotations

import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

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
aws_access_token: str = ""   # AWS Access Key ID
aws_secret_token: str = ""   # AWS Secret Access Key
aws_session_token: str = ""  # Optional (only for temp creds)
account_id: str = ""
owner: str = ""              # Must match IAM username if policy enforces aws:RequestTag/Owner == ${aws:username}

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
    if not k:
        return "<empty>"
    return ("*" * max(0, len(k) - 4)) + k[-4:]


def _mask_pat(p: str) -> str:
    if not p:
        return "<empty>"
    # keep last 4
    return ("*" * max(0, len(p) - 4)) + p[-4:]


# ---------------------------------------------------------------------
# Robust .env parsing (dotenv and python-like, with inline comment safety)
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
    """
    Supports:
      1) dotenv: KEY=VALUE (quoted/unquoted, supports inline comments)
      2) python-like: KEY: str = "VALUE"   # comments allowed
    """
    if not env_path.exists():
        raise FileNotFoundError(f"Missing {ENV_FILE_NAME} next to driver.py: {env_path}")

    data: dict[str, str] = {}
    lines = env_path.read_text(encoding="utf-8", errors="replace").splitlines()

    py_like = re.compile(r"""^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*str\s*=\s*(.+?)\s*$""")

    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        if line.lower().startswith("export "):
            line = line[7:].strip()

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
    global account_id, owner
    global devops_repo_url, backend_repo_url, frontend_repo_url
    global git_username, git_pat

    def pick(*names: str) -> str:
        for n in names:
            if n in data and str(data[n]).strip():
                return str(data[n]).strip()
        return ""

    # Core AWS/account
    aws_region = pick("AWS_REGION", "aws_region")
    aws_access_token = pick("AWS_ACCESS_TOKEN", "aws_access_token", "AWS_ACCESS", "aws_access")
    aws_secret_token = pick("AWS_SECRET_TOKEN", "aws_secret_token", "AWS_SECRET", "aws_secret")
    aws_session_token = pick("AWS_SESSION_TOKEN", "aws_session_token")  # optional
    account_id = pick("ACCOUNT_ID", "account_id")
    owner = pick("OWNER", "owner")

    # Repo URLs
    devops_repo_url = pick("DEVOPS_REPO_URL", "devops_repo_url")
    # backend: accept BACKEND_REPO_URL or API_REPO_URL (your env has both)
    backend_repo_url = pick("BACKEND_REPO_URL", "backend_repo_url", "API_REPO_URL", "api_repo_url")
    frontend_repo_url = pick("FRONTEND_REPO_URL", "frontend_repo_url")

    # Git creds: accept either GITHUB_* or GIT_*
    git_username = pick("GITHUB_USER", "GIT_USERNAME", "git_username")
    git_pat = pick("GITHUB_PAT", "GIT_PAT", "git_pat")

    missing = []
    # Required for terraform provisioning
    if not aws_region:
        missing.append("AWS_REGION")
    if not aws_access_token:
        missing.append("AWS_ACCESS_TOKEN")
    if not aws_secret_token:
        missing.append("AWS_SECRET_TOKEN")
    if not account_id:
        missing.append("ACCOUNT_ID")
    if not owner:
        missing.append("OWNER")
    if not devops_repo_url:
        missing.append("DEVOPS_REPO_URL")
    if not backend_repo_url:
        missing.append("BACKEND_REPO_URL (or API_REPO_URL)")
    if not frontend_repo_url:
        missing.append("FRONTEND_REPO_URL")

    # Git creds are often required if repos are private; keep them required if you want strictness.
    # If your repos are public, you can remove these two checks.
    if not git_username:
        missing.append("GITHUB_USER (or GIT_USERNAME)")
    if not git_pat:
        missing.append("GITHUB_PAT (or GIT_PAT)")

    if missing:
        raise ValueError(f"{ENV_FILE_NAME} is missing required keys: {', '.join(missing)}")


def _print_loaded_env(env_path: Path) -> None:
    print("\nLoaded configuration from .env")
    print("-" * 70)
    print(f".env path:         {env_path}")
    print(f"AWS_REGION:        {aws_region}")
    print(f"AWS_ACCESS_TOKEN:  {_mask_access_key(aws_access_token)}")
    print("AWS_SECRET_TOKEN:  ************")
    print(f"AWS_SESSION_TOKEN: {'yes' if aws_session_token else 'no'}")
    print(f"ACCOUNT_ID:        {account_id}")
    print(f"OWNER:             {owner}")
    print(f"DEVOPS_REPO_URL:   {devops_repo_url}")
    print(f"BACKEND_REPO_URL:  {backend_repo_url}")
    print(f"FRONTEND_REPO_URL: {frontend_repo_url}")
    print(f"GIT_USERNAME:      {git_username}")
    print(f"GIT_PAT:           {_mask_pat(git_pat)}")
    print("-" * 70)


# ---------------------------------------------------------------------
# Dynamic repo/infra detection
# ---------------------------------------------------------------------
def _find_devops_repo_root_from_script_location(script_dir: Path) -> Path:
    """
    Walk up from driver.py location until we find a folder containing .git.
    """
    cur = script_dir.resolve()
    for _ in range(20):
        if (cur / ".git").exists():
            return cur
        if cur.parent == cur:
            break
        cur = cur.parent

    raise RuntimeError(
        "Could not locate DevOps repo root (.git) by walking up from driver.py.\n"
        "Place driver.py inside the CloudRift-devops repository (any subfolder)."
    )


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

    if not setup_candidates:
        raise FileNotFoundError(f"Could not find {SETUP_SH} under {devops_repo_root}")
    if not destroy_candidates:
        raise FileNotFoundError(f"Could not find {DESTROY_SH} under {devops_repo_root}")

    setup_dirs = {p.parent.resolve(): p.resolve() for p in setup_candidates}
    destroy_dirs = {p.parent.resolve(): p.resolve() for p in destroy_candidates}
    common = set(setup_dirs.keys()) & set(destroy_dirs.keys())

    if common:
        infra = sorted(common, key=lambda x: len(str(x)))[0]
        return infra, setup_dirs[infra], destroy_dirs[infra]

    # fallback
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
    print(f"DevOps repo root:         {p.devops_repo_root}")
    print(f"Infra directory:          {p.infra_dir}")
    print(f"setup.sh:                 {p.setup_sh}")
    print(f"destroy.sh:               {p.destroy_sh}")
    print(f"DEV credentials.auto:     {p.dev_credentials_tfvars}")
    print(f"DEV terraform.tfvars:     {p.dev_terraform_tfvars}")
    print("-" * 70)


# ---------------------------------------------------------------------
# tfvars writing
# ---------------------------------------------------------------------
def _credentials_tfvars_content() -> str:
    # We write ALL dynamic/sensitive variables here.
    # Since this is an .auto.tfvars file, it overrides everything else.
    lines = [
        # AWS Credentials
        f'aws_access_key = "{aws_access_token}"',
        f'aws_secret_key = "{aws_secret_token}"',
        f'region = "{aws_region}"',

        # --- FIX: Add Account ID and Owner here ---
        f'account_id = "{account_id}"',
        f'owner = "{owner}"',
        # ------------------------------------------

        # Git/Repo Variables
        f'devops_repo_url = "{devops_repo_url}"',
        f'backend_repo_url = "{backend_repo_url}"',
        f'frontend_repo_url = "{frontend_repo_url}"',
        f'git_username = "{git_username}"',
        f'git_pat = "{git_pat}"',
    ]

    if aws_session_token:
        lines.append(f'aws_session_token = "{aws_session_token}"')

    return "\n".join(lines) + "\n"


def _write_credentials(p: RepoPaths) -> None:
    p.dev_credentials_tfvars.parent.mkdir(parents=True, exist_ok=True)
    p.dev_credentials_tfvars.write_text(_credentials_tfvars_content(), encoding="utf-8", newline="\n")
    print(f"Wrote: {p.dev_credentials_tfvars}")


def _upsert_tfvars_kv(tfvars_path: Path, key: str, value: str) -> None:
    tfvars_path.parent.mkdir(parents=True, exist_ok=True)
    existing = tfvars_path.read_text(encoding="utf-8", errors="replace") if tfvars_path.exists() else ""

    text = existing.replace("\r\n", "\n").replace("\r", "\n")
    if text and not text.endswith("\n"):
        text += "\n"

    pattern = re.compile(rf'(?m)^\s*{re.escape(key)}\s*=\s*(".*?"|[^\n#]+)\s*(#.*)?$')
    new_line = f'{key} = "{value}"\n'

    if pattern.search(text):
        text = pattern.sub(new_line.rstrip("\n"), text)
        if not text.endswith("\n"):
            text += "\n"
    else:
        text += new_line

    tfvars_path.write_text(text, encoding="utf-8", newline="\n")




# ---------------------------------------------------------------------
# Git Bash execution
# ---------------------------------------------------------------------
def _resolve_bash_path() -> Path:
    candidate = Path(DEFAULT_GIT_BASH)
    if candidate.exists():
        return candidate

    which = shutil.which("bash")
    if which:
        return Path(which)

    raise FileNotFoundError(f"Git Bash not found at {DEFAULT_GIT_BASH} and 'bash' not found in PATH.")


def _clean_env_for_subprocess() -> dict[str, str]:
    env = dict(os.environ)

    # Ensure terraform uses the tfvars we write, not the user's env/profile
    for k in (
        "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
        "AWS_PROFILE", "AWS_DEFAULT_PROFILE",
    ):
        env.pop(k, None)

    env["TF_IN_AUTOMATION"] = "1"

    # This is the key part: Terraform gets the required module variables from your LOCAL .env
    env["TF_VAR_devops_repo_url"] = devops_repo_url
    env["TF_VAR_backend_repo_url"] = backend_repo_url
    env["TF_VAR_frontend_repo_url"] = frontend_repo_url

    # Only include these if your Terraform module actually declares these variables.
    # (Your dev main.tf shows git_username/git_pat are being passed, so you DO want these.)
    env["TF_VAR_git_username"] = git_username
    env["TF_VAR_git_pat"] = git_pat

    return env


def _run_bash_script(bash_path: Path, script_name: str, cwd: Path, auto_confirm: bool) -> None:
    """
    - Normalizes CRLF to LF
    - Runs script
    - If auto_confirm=True, feeds "yes" to satisfy terraform prompts
    """
    script_path = cwd / script_name
    if not script_path.exists():
        raise FileNotFoundError(f"Script not found: {script_path}")

    cmd = [
        str(bash_path),
        "-lc",
        f"sed -i 's/\\r$//' {script_name}; bash {script_name}",
    ]

    stdin_payload = ("yes\n" * 200) if auto_confirm else None

    print(f"\nExecuting in: {cwd}")
    print(f'Command: {bash_path} -lc "sed -i \'s/\\r$//\' {script_name}; bash {script_name}"')

    result = subprocess.run(
        cmd,
        cwd=str(cwd),
        text=True,
        env=_clean_env_for_subprocess(),
        input=stdin_payload,
    )
    if result.returncode != 0:
        raise RuntimeError(f"{script_name} failed with exit code {result.returncode}")


# ---------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------
def _preflight_aws_identity(bash_path: Path, cwd: Path) -> None:
    cmd = [
        str(bash_path),
        "-lc",
        "command -v aws >/dev/null 2>&1 && aws sts get-caller-identity || echo 'AWS CLI not found; skipping sts check.'"
    ]

    env = _clean_env_for_subprocess()
    env["AWS_ACCESS_KEY_ID"] = aws_access_token
    env["AWS_SECRET_ACCESS_KEY"] = aws_secret_token
    if aws_session_token:
        env["AWS_SESSION_TOKEN"] = aws_session_token
    env["AWS_DEFAULT_REGION"] = aws_region

    subprocess.run(cmd, cwd=str(cwd), text=True, env=env, check=False)


# ---------------------------------------------------------------------
# Flows
# ---------------------------------------------------------------------
def _provision(p: RepoPaths, bash_path: Path) -> None:
    print("\n[Provision] Writing tfvars and running setup.sh...")
    _preflight_aws_identity(bash_path, p.infra_dir)
    _write_credentials(p)
    _run_bash_script(bash_path, SETUP_SH, p.infra_dir, auto_confirm=False)
    print("[Provision] Completed successfully.")


def _destroy(p: RepoPaths, bash_path: Path) -> None:
    print("\n[Destroy] Writing tfvars and running destroy.sh (auto-confirm enabled)...")
    _preflight_aws_identity(bash_path, p.infra_dir)
    _write_credentials(p)
    _run_bash_script(bash_path, DESTROY_SH, p.infra_dir, auto_confirm=True)
    print("[Destroy] Completed successfully.")


# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------
def main() -> int:
    # Header before load (shows placeholders)
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
        print("1) Provision / Apply infrastructure (setup.sh)")
        print("2) Destroy infrastructure (destroy.sh)  [deletes everything in Terraform state]")
        print("0) Exit")

        choice = input("> ").strip()

        try:
            if choice == "1":
                _provision(paths, bash_path)
            elif choice == "2":
                _destroy(paths, bash_path)
            elif choice == "0":
                print("Exiting.")
                return 0
            else:
                print("Invalid selection. Choose 0, 1, or 2.")
        except Exception as e:
            print(f"\nERROR: {e}")
            if not _prompt_yes_no("Return to menu?", default_yes=True):
                return 1


if __name__ == "__main__":
    raise SystemExit(main())
