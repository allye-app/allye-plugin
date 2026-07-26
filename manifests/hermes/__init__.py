"""Allye bootstrap for Hermes Agent."""
# installed by the Allye plugin installer
# edit the source at manifests/hermes/, not this copy — reinstalling overwrites it
# ALLYE_INSTALLER_VERSION=1

from __future__ import annotations

import os
from pathlib import Path

_SKILL = Path.home() / ".hermes" / "skills" / "allye" / "using-allye" / "SKILL.md"


def _bootstrap(ctx, *_args, **_kwargs):
    """Inject the Allye bootstrap skill once, at session start.

    Reads from disk rather than over MCP: Hermes may not have completed MCP
    discovery when this fires, and a bootstrap that sometimes arrives is worse
    than one that always does.
    """
    try:
        if not _SKILL.is_file():
            return
        ctx.inject_message(_SKILL.read_text(encoding="utf-8"), role="user")
    except Exception:
        # A failed bootstrap must never break the session. The agent works
        # without the methodology; it does not work if startup raises.
        pass


def register(ctx):
    ctx.register_hook("on_session_start", _bootstrap)
