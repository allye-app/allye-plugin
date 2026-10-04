// Guards the native crew agents in agents/: one per crew skill, same description,
// and tool allowlists that never exceed the role's mandate. Offline, no dependencies.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const agentsDir = join(root, "agents");
const PREFIX = "Only when dispatched by the Bridge Mothership —";
const MCP = "mcp__plugin_allye_allye__";
const ALLYE_READS = ["projects", "epics", "specs", "tasks"];
const NO_FILE_EDITS = ["armorer", "recon", "strategist", "architect", "copilot", "medic", "optimizer", "shield", "watcher"];
const NO_BASH = ["strategist", "architect", "dispatcher"];
const EDIT_TOOLS = ["Edit", "Write", "MultiEdit", "NotebookEdit"];
const NEVER = ["Agent", "Task", "AskUserQuestion", `${MCP}team`];
const SUPPORTED_FIELDS = new Set(["name", "description", "tools", "disallowedTools", "model", "effort", "maxTurns", "skills", "color"]);

const errors = [];
const fail = (msg) => errors.push(msg);

function frontmatter(text, file) {
  const match = text.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) return fail(`${file}: missing frontmatter`), null;
  const fields = {};
  for (const line of match[1].split("\n")) {
    const kv = line.match(/^([A-Za-z]+):\s*(.*)$/);
    if (!kv) return fail(`${file}: unparseable frontmatter line: ${line}`), null;
    if (kv[1] in fields) fail(`${file}: duplicate field ${kv[1]}`);
    fields[kv[1]] = kv[2];
  }
  return { fields, body: text.slice(match[0].length) };
}

const crewSkills = readdirSync(join(root, "skills")).filter((n) => n.startsWith("bridge-")).sort();
const agentFiles = existsSync(agentsDir) ? readdirSync(agentsDir).filter((n) => n.endsWith(".md")).sort() : [];
if (agentFiles.length === 0) fail("agents/ has no agent definitions");

for (const file of agentFiles) {
  const name = file.replace(/\.md$/, "");
  const parsed = frontmatter(readFileSync(join(agentsDir, file), "utf8"), file);
  if (!parsed) continue;
  const { fields, body } = parsed;
  for (const key of Object.keys(fields)) if (!SUPPORTED_FIELDS.has(key)) fail(`${file}: frontmatter field '${key}' is not supported for plugin agents`);
  if (fields.name !== name) fail(`${file}: name '${fields.name}' does not match the file name`);
  const skillDir = join(root, "skills", name);
  if (!existsSync(join(skillDir, "SKILL.md"))) { fail(`${file}: no matching skills/${name}/SKILL.md`); continue; }
  if (!fields.description?.startsWith(PREFIX)) fail(`${file}: description must start with "${PREFIX}"`);
  const skillDescription = readFileSync(join(skillDir, "SKILL.md"), "utf8").match(/^description: (.*)$/m)?.[1];
  if (fields.description !== skillDescription) fail(`${file}: description differs from skills/${name}/SKILL.md (copy it verbatim)`);
  if (!body.includes(`allye:${name}`) || !body.includes(`skills/${name}/SKILL.md`)) fail(`${file}: body must load skill allye:${name} with the SKILL.md fallback`);

  if (!fields.tools) { fail(`${file}: tools allowlist is required (omitting it inherits every tool)`); continue; }
  const tools = fields.tools.split(",").map((t) => t.trim()).filter(Boolean);
  if (new Set(tools).size !== tools.length) fail(`${file}: duplicate tools`);
  const role = name.replace(/^bridge-/, "");
  if (!tools.includes("Skill")) fail(`${file}: needs the Skill tool to load its skill`);
  for (const tool of tools) {
    if (NEVER.includes(tool)) fail(`${file}: ${tool} is reserved to the Mothership`);
    if (tool.includes("*") || tool === MCP.replace(/__$/, "")) fail(`${file}: wildcard tool grants are not allowed (${tool})`);
    if (tool.startsWith("mcp__") && !tool.startsWith(MCP)) fail(`${file}: MCP tool from another server: ${tool}`);
  }
  if (NO_FILE_EDITS.includes(role)) for (const t of EDIT_TOOLS) if (tools.includes(t)) fail(`${file}: read-only role must not have ${t}`);
  if (NO_BASH.includes(role) && tools.includes("Bash")) fail(`${file}: ${role} runs no commands and must not have Bash`);
  const mcp = tools.filter((t) => t.startsWith(MCP)).map((t) => t.slice(MCP.length)).sort();
  const expected = role === "armorer" ? ["allye_health_check", "initialize", "skills"] : [...ALLYE_READS].sort();
  if (mcp.join() !== expected.join()) fail(`${file}: Allye MCP tools [${mcp}] must be exactly [${expected}] (delegation.md → Allye MCP access)`);
}

for (const skill of crewSkills) if (!agentFiles.includes(`${skill}.md`)) fail(`skills/${skill} has no agents/${skill}.md`);

if (errors.length) {
  for (const e of errors) console.error(`FAIL: ${e}`);
  process.exit(1);
}
console.log(`agents: ok (${agentFiles.length} crew agents, one per crew skill)`);
