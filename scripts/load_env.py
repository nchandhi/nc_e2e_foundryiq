"""
load_env.py — Environment loader utility
Loads environment variables from two sources (in order):
  1. azd environment (.azure/<env>/.env) — Azure service endpoints from 'azd up'
  2. Project .env file (scripts/.env) — your local overrides (DATA_FOLDER, etc.)

Adapted from the accelerator repo, simplified to remove Fabric/SQL dependencies.

Usage in other scripts:
    from load_env import load_all_env, get_data_folder
    load_all_env()
"""

import os
import sys
import subprocess
from pathlib import Path
from dotenv import load_dotenv


def get_project_root() -> Path:
    """Find the project root (where azure.yaml or .azure/ lives)."""
    # Start from the scripts folder and walk up
    current = Path(__file__).resolve().parent
    for _ in range(5):  # Don't go more than 5 levels up
        if (current / "azure.yaml").exists() or (current / ".azure").exists():
            return current
        current = current.parent
    # Fallback: assume scripts/ is one level below root
    return Path(__file__).resolve().parent.parent


def load_azd_env():
    """Load environment variables from the active azd environment.

    azd stores outputs from Bicep in .azure/<env>/.env after 'azd up'.
    This gives us AZURE_AI_SEARCH_ENDPOINT, AZURE_OPENAI_ENDPOINT, etc.
    """
    try:
        result = subprocess.run(
            ["azd", "env", "get-values"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            for line in result.stdout.strip().splitlines():
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    key, _, value = line.partition("=")
                    key = key.strip()
                    value = value.strip().strip('"').strip("'")
                    if key and value:
                        os.environ.setdefault(key, value)
            return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass  # azd not installed or not configured — that's fine
    return False


def load_project_env():
    """Load the project .env file (scripts/.env or root .env).

    These are your local overrides — DATA_FOLDER, SOLUTION_NAME, etc.
    Uses setdefault so azd values take priority.
    """
    script_dir = Path(__file__).resolve().parent
    project_root = get_project_root()

    # Try scripts/.env first, then root .env
    for env_path in [script_dir / ".env", project_root / ".env"]:
        if env_path.exists():
            load_dotenv(env_path, override=False)  # Don't override existing vars
            return True
    return False


def load_all_env():
    """Load all environment sources. Call this at the top of every script."""
    azd_loaded = load_azd_env()
    project_loaded = load_project_env()

    if azd_loaded:
        print("[env] Loaded azd environment")
    if project_loaded:
        print("[env] Loaded project .env")
    if not azd_loaded and not project_loaded:
        print("[env] WARNING: No environment files found")
        print("       Run 'azd up' first, or create scripts/.env from .env.example")


def get_required_env(key: str) -> str:
    """Get an environment variable or exit with an error."""
    value = os.getenv(key)
    if not value:
        print(f"ERROR: {key} not set")
        print("       Run 'azd up' to deploy Azure resources, or set it in .env")
        sys.exit(1)
    return value


def get_data_folder() -> str:
    """Get the absolute path to the data folder.

    Resolves DATA_FOLDER relative to the project root.
    Returns: Absolute path string.
    Raises: ValueError if DATA_FOLDER is not set.
    """
    data_folder = os.getenv("DATA_FOLDER")
    if not data_folder:
        raise ValueError("DATA_FOLDER not set in .env")

    data_path = Path(data_folder)
    if not data_path.is_absolute():
        data_path = get_project_root() / data_path

    return str(data_path.resolve())


def print_env_status():
    """Print which key environment variables are set (for debugging)."""
    keys = [
        "AZURE_AI_AGENT_ENDPOINT",
        "AZURE_AI_SEARCH_ENDPOINT",
        "AZURE_OPENAI_ENDPOINT",
        "AZURE_OPENAI_CHAT_MODEL",
        "AZURE_OPENAI_EMBEDDING_MODEL",
        "AZURE_AI_SEARCH_CONNECTION_NAME",
        "AZURE_AI_PROJECT_NAME",
        "AI_SERVICE_NAME",
        "DATA_FOLDER",
    ]
    print("\nEnvironment status:")
    for key in keys:
        val = os.getenv(key)
        if val:
            # Truncate long values
            display = val if len(val) < 60 else val[:57] + "..."
            print(f"  {key} = {display}")
        else:
            print(f"  {key} = (not set)")
