"""
Utility functions for logging and async operations.

These utilities are shared across all integration test suites.
"""

import asyncio
import os
from typing import Awaitable, Callable, TypeVar

from tenacity import (
    AsyncRetrying,
    RetryError,
    stop_after_attempt,
    stop_after_delay,
    wait_fixed,
)

T = TypeVar("T")


def log_info(message: str) -> None:
    """Log an info message."""
    print(f"✅ {message}")


def log_error(message: str) -> None:
    """Log an error message."""
    print(f"❌ error: {message}")


def log_warning(message: str) -> None:
    """Log a warning message."""
    print(f"⚠️ Warning: {message}")


async def wait_for_condition(
    condition_func: Callable[[], Awaitable[T]],
    timeout_seconds: int = 300,
    interval_seconds: int = 5,
    description: str = "condition",
) -> T:
    """
    Wait for a condition to be met, with retries.

    Args:
        condition_func: Async function that returns a truthy value when condition is met,
                       or raises an exception if it should retry.
        timeout_seconds: Maximum time to wait.
        interval_seconds: Time between retries.
        description: Human-readable description for logging.

    Returns:
        The value returned by condition_func when it succeeds.

    Raises:
        TimeoutError: If the condition is not met within the timeout.
    """
    print(f"Waiting for {description} (timeout: {timeout_seconds}s)...")

    try:
        async for attempt in AsyncRetrying(
            stop=stop_after_delay(timeout_seconds),
            wait=wait_fixed(interval_seconds),
            reraise=True,
        ):
            with attempt:
                result = await condition_func()
                if not result:
                    raise ValueError(f"{description} not ready yet")
                return result
    except RetryError as e:
        raise TimeoutError(
            f"Timeout waiting for {description} after {timeout_seconds}s"
        ) from e


async def run_with_retry(
    func: Callable[[], Awaitable[T]],
    max_attempts: int = 3,
    delay_seconds: int = 5,
    description: str = "operation",
) -> T:
    """
    Run an async function with retries.

    Args:
        func: Async function to run.
        max_attempts: Maximum number of attempts.
        delay_seconds: Delay between attempts.
        description: Human-readable description for logging.

    Returns:
        The value returned by func when it succeeds.
    """
    try:
        async for attempt in AsyncRetrying(
            stop=stop_after_attempt(max_attempts),
            wait=wait_fixed(delay_seconds),
            reraise=True,
        ):
            with attempt:
                print(
                    f"{description} (attempt {attempt.retry_state.attempt_number}/{max_attempts})"
                )
                return await func()
    except RetryError:
        log_error(f"Failed {description} after {max_attempts} attempts")
        raise


async def run_command(
    cmd: list[str],
    check: bool = True,
    capture_output: bool = True,
    env: dict[str, str] | None = None,
    cwd: str | None = None,
) -> tuple[int, str, str]:
    """
    Run a shell command asynchronously.

    Args:
        cmd: Command and arguments as a list.
        check: If True, raise exception on non-zero exit.
        capture_output: If True, capture stdout/stderr.
        env: Optional environment variables to add.
        cwd: Optional working directory.

    Returns:
        Tuple of (return_code, stdout, stderr).
    """
    full_env = os.environ.copy()
    if env:
        full_env.update(env)

    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE if capture_output else None,
        stderr=asyncio.subprocess.PIPE if capture_output else None,
        env=full_env,
        cwd=cwd,
    )

    stdout_bytes, stderr_bytes = await process.communicate()
    stdout = stdout_bytes.decode() if stdout_bytes else ""
    stderr = stderr_bytes.decode() if stderr_bytes else ""

    if check and process.returncode != 0:
        raise RuntimeError(
            f"Command {' '.join(cmd)} failed with code {process.returncode}: {stderr}"
        )

    return process.returncode, stdout, stderr
