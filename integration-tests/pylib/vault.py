"""
Secrets management for integration tests.

Handles decryption of ansible-vault encrypted secrets.
"""

from pathlib import Path

from .utils import log_info, run_command


async def decrypt_secrets(suite_dir: Path, vault_password_file: str) -> None:
    """
    Decrypt ansible-vault secrets if they don't already exist.

    Args:
        suite_dir: Path to the test suite directory.
        vault_password_file: Path to the vault password file.
    """
    tenant_secrets_dir = suite_dir / "resources" / "tenant" / "secrets"
    managed_secrets_dir = suite_dir / "resources" / "managed" / "secrets"

    tenant_secrets_dir.mkdir(parents=True, exist_ok=True)
    managed_secrets_dir.mkdir(parents=True, exist_ok=True)

    tenant_secrets_file = tenant_secrets_dir / "tenant-secrets.yaml"
    managed_secrets_file = managed_secrets_dir / "managed-secrets.yaml"

    vault_dir = suite_dir / "vault"

    # Decrypt tenant secrets if needed
    if not tenant_secrets_file.exists():
        vault_file = vault_dir / "tenant-secrets.yaml"
        if vault_file.exists():
            log_info(f"Decrypting tenant secrets from {vault_file}")
            await run_command(
                [
                    "ansible-vault",
                    "decrypt",
                    str(vault_file),
                    "--output",
                    str(tenant_secrets_file),
                    "--vault-password-file",
                    vault_password_file,
                ]
            )
    else:
        log_info("Tenant secrets already exist")

    # Decrypt managed secrets if needed
    if not managed_secrets_file.exists():
        vault_file = vault_dir / "managed-secrets.yaml"
        if vault_file.exists():
            log_info(f"Decrypting managed secrets from {vault_file}")
            await run_command(
                [
                    "ansible-vault",
                    "decrypt",
                    str(vault_file),
                    "--output",
                    str(managed_secrets_file),
                    "--vault-password-file",
                    vault_password_file,
                ]
            )
    else:
        log_info("Managed secrets already exist")

    log_info("Secret decryption complete")


async def cleanup_decrypted_secrets(suite_dir: Path) -> None:
    """
    Remove decrypted secrets files.

    Args:
        suite_dir: Path to the test suite directory.
    """
    tenant_secrets_file = (
        suite_dir / "resources" / "tenant" / "secrets" / "tenant-secrets.yaml"
    )
    managed_secrets_file = (
        suite_dir / "resources" / "managed" / "secrets" / "managed-secrets.yaml"
    )

    for secrets_file in [tenant_secrets_file, managed_secrets_file]:
        if secrets_file.exists():
            secrets_file.unlink()
            log_info(f"Removed decrypted secrets: {secrets_file}")
