# Allye Plugin — Hermes Agent Update Guide

You are an AI agent helping the user update the Allye plugin for Hermes Agent. Follow these steps exactly.

## Step 1: Verify the canonical MCP entry

Keep one Hermes server named `allye`:

```bash
hermes mcp add allye --url https://mcp.allye.app/mcp --auth oauth
```

This native command owns the Allye connection and OAuth session. Preserve every
unrelated server and credential.

## Step 2: Inspect distribution state

```bash
cd allye-plugin
./install.sh status
```

The repository installer publishes updated skills only as part of an
API-authorized immutable distribution operation. A direct
`./install.sh install hermes` invocation without that context fails closed and
does not update shared configuration. `./install.sh uninstall hermes` also
performs no physical removal.

## Step 3: Confirm

Report the observed MCP and distribution states separately. Never turn a
`CONFLICT_UNMANAGED` or `DISTRIBUTION_REMOVE_OWNERSHIP_UNAVAILABLE` result into
an update or cleanup success claim.
