/**
 * Fetches user context from the Fenix MCP server via JSON-RPC.
 * Injected into the system prompt before every conversation.
 *
 * This calls the `initialize` action to get user profile, teams,
 * core documents, and user documents — the same data the agent
 * would get by calling `initialize` manually.
 */

import { readFileSync, existsSync } from "fs"
import { join } from "path"
import { homedir } from "os"

const MCP_URL = "https://fenix-mcp.devshire.app/jsonrpc"

// Cache context per process to avoid re-fetching on every message
let cachedContext: string | null = null
let cacheTimestamp = 0
const CACHE_TTL = 5 * 60 * 1000 // 5 minutes

/**
 * Reads the Fenix PAT from environment or OpenCode config.
 */
function getFenixPat(): string | null {
  // Try environment variable first
  const envPat = process.env.FENIX_PAT || process.env.FENIX_PAT_TOKEN
  if (envPat) return envPat

  // Try reading from opencode config
  try {
    const configPaths = [
      join(process.cwd(), "opencode.json"),
      join(
        process.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
        "opencode",
        "opencode.json",
      ),
    ]

    for (const configPath of configPaths) {
      if (existsSync(configPath)) {
        const config = JSON.parse(readFileSync(configPath, "utf-8"))
        const fenixMcp = config?.mcp?.["fenix-mcp"]
        if (fenixMcp?.headers?.Authorization) {
          return fenixMcp.headers.Authorization.replace("Bearer ", "")
        }
      }
    }
  } catch {
    // Silently fail
  }

  return null
}

/**
 * Calls the Fenix MCP server's initialize action via JSON-RPC.
 */
async function callInitialize(pat: string): Promise<string | null> {
  try {
    const response = await fetch(MCP_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${pat}`,
      },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "initialize",
          arguments: {
            action: "init",
            include_user_docs: true,
          },
        },
      }),
      signal: AbortSignal.timeout(10000),
    })

    if (!response.ok) return null

    const data = (await response.json()) as {
      result?: { content?: Array<{ text?: string }> }
    }
    const text = data?.result?.content?.[0]?.text
    return text || null
  } catch {
    return null
  }
}

/**
 * Fetches and formats the Fenix context for system prompt injection.
 * Results are cached for 5 minutes to avoid redundant API calls.
 */
export async function fetchFenixContext(): Promise<string | null> {
  // Check cache
  if (cachedContext && Date.now() - cacheTimestamp < CACHE_TTL) {
    return cachedContext
  }

  const pat = getFenixPat()
  if (!pat) return null

  const initResult = await callInitialize(pat)
  if (!initResult) return null

  const context = `<fenix-context>
# Fenix User Context (auto-loaded)

${initResult}

## Instructions

You are connected to the Fenix platform. The user context above was loaded automatically.
- You already know who the user is — greet them by their preferred name
- Search for relevant memories before starting work
- Load team-specific skills via \`skill_list\` for the current task
- Save session state before ending
</fenix-context>`

  cachedContext = context
  cacheTimestamp = Date.now()

  return context
}
