#!/usr/bin/env bash
# Retired fail-closed entrypoint. Physical distributions run only through
# install_skills_to_disk(), where JWKS/JWS preflight and atomic rollback exist.
printf '%s\n' 'Standalone distribution wrapper is disabled; use the installer disk boundary with an execution context.' >&2
exit 2
