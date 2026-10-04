# Allye — OpenCode update guide

You are an AI agent helping the user update the `allye-opencode` plugin.

## Step 1: Update the npm package

```bash
cd ~/.config/opencode && (bun update allye-opencode 2>/dev/null || npm update allye-opencode)
```

If that does not pick up the new version, reinstall it:

```bash
cd ~/.config/opencode && rm -rf node_modules/allye-opencode && (bun install 2>/dev/null || npm install)
```

## Step 2: Verify

```bash
jq -r '.version' ~/.config/opencode/node_modules/allye-opencode/package.json
npm view allye-opencode version
```

Both versions must match. Earlier versions registered six Allye agents (Allye, Plan, Orchestrator, Build, Review, Deliver); they disappear after the update, replaced by the Bridge skill.

## Step 3: Confirm

> Allye plugin updated to version **{version}**. Restart OpenCode to load it.
