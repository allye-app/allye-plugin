# Fenix Plugin — OpenCode Update Guide

You are an AI agent helping the user update the Fenix plugin for OpenCode. Follow these steps exactly.

## Step 1: Update the npm package

Run this command to update fenix-opencode to the latest version:

```bash
cd ~/.config/opencode && bun update fenix-opencode 2>/dev/null || npm update fenix-opencode 2>/dev/null
```

If that doesn't work, force a clean reinstall:

```bash
cd ~/.config/opencode && rm -rf node_modules/fenix-opencode && bun install 2>/dev/null || npm install 2>/dev/null
```

## Step 2: Verify the update

Check the installed version:

```bash
cat ~/.config/opencode/node_modules/fenix-opencode/package.json 2>/dev/null | jq -r '.version'
```

Check the latest version on npm:

```bash
npm view fenix-opencode version
```

If both match, the update is complete.

## Step 3: Confirm

Tell the user:

> Fenix plugin updated to version **{version}**!
>
> **Restart OpenCode** to activate the new version.
