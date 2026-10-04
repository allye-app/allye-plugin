# Allye — OpenCode installation guide

You are an AI agent helping the user install Allye for OpenCode: the Allye MCP server and the `allye-opencode` plugin, which adds the Allye bootstrap and the Bridge skill. Preserve unrelated MCP servers, plugins and credentials.

## Step 1: Configure the MCP server and the plugin

Merge the Allye entries into the user's OpenCode config. If the config still has the legacy `allye-mcp` entry, first run `opencode mcp logout allye-mcp` (this clears only that obsolete registration).

```bash
CONFIG=$(cat ~/.config/opencode/opencode.json 2>/dev/null || echo '{"$schema": "https://opencode.ai/config.json"}')

CONFIG=$(echo "$CONFIG" | jq '
  .mcp = (.mcp // {})
  | del(.mcp["allye-mcp"])
  | .mcp.allye = { "type": "remote", "url": "https://mcp.allye.app/mcp", "enabled": true }
  | .plugin = (.plugin // [])
  | if (.plugin | index("allye-opencode")) then . else .plugin += ["allye-opencode"] end
')

mkdir -p ~/.config/opencode
echo "$CONFIG" | jq '.' > ~/.config/opencode/opencode.json
```

The `allye` entry intentionally has no headers or fixed OAuth client metadata.

## Step 2: Authenticate

Restart OpenCode, then:

```bash
opencode mcp auth allye
opencode mcp list
```

OpenCode owns discovery, client registration, token storage and refresh.

## Step 3: Confirm

Tell the user:

> Allye is configured for OpenCode:
> - the `allye` MCP server at `https://mcp.allye.app/mcp`, using native OAuth;
> - the `allye-opencode` plugin, which adds the Allye bootstrap and the Bridge skill (`/bridge <mode>`).
>
> Restart OpenCode to load the plugin. If no Allye team is active, the agent will ask which one to use.
