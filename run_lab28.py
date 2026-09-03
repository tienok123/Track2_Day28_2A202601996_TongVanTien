"""Run lab28 commands with proper encoding."""

import sys
from pathlib import Path

from typer.testing import CliRunner

# Ensure the ``src/`` layout is importable when the shim is invoked as a plain
# script (``python run_lab28.py ...``). Without this, Python only searches the
# current working directory, so ``from lab28_platform.cli import app`` fails
# with ``ModuleNotFoundError`` on local Windows machines.
_SRC_DIR = Path(__file__).resolve().parent / "src"
if _SRC_DIR.is_dir():
    src_str = str(_SRC_DIR)
    if src_str not in sys.path:
        sys.path.insert(0, src_str)

from lab28_platform.cli import app

# Typer prints commentary to stderr via ``typer.secho`` and exception tracebacks
# arrive on stderr as well. On Windows PowerShell the default encoding is cp1252
# and cannot encode the Vietnamese prompt template that ships with the platform,
# which makes the very first command crash before the test runner ever sees the
# output. Reconfigure both streams at import time so the encoding is correct for
# every run, including ``python -m lab28_platform.cli`` invocations that bypass
# this shim.
try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
    sys.stderr.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except (AttributeError, ValueError):
    # Python < 3.7 or already-closed streams in some test harnesses.
    pass

runner = CliRunner()
result = runner.invoke(app, sys.argv[1:])

with open('lab28_output.txt', 'w', encoding='utf-8') as f:
    f.write(f"exit_code: {result.exit_code}\n")
    f.write(f"stdout:\n{result.stdout}\n")
    if result.exception:
        import traceback
        f.write(f"\nexception:\n{traceback.format_exception(result.exception)}\n")

sys.stdout.write(result.output)
if result.exit_code != 0:
    sys.exit(result.exit_code)
