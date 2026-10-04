import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";
import {
  buildSystemSections,
  inspectTeamSelection,
  loadBootstrap,
  mcpBridgeAvailable,
  skillsPath,
  unavailableStartupContext,
} from "./index.ts";

test("bootstrap is the shared bootstrap/allye.md text", () => {
  const shared = readFileSync(resolve(import.meta.dirname, "../../../bootstrap/allye.md"), "utf8");
  assert.equal(loadBootstrap(), shared);
  assert.match(loadBootstrap(), /\/bridge <mode>/);
  assert.match(loadBootstrap(), /team_switch/);
});

test("skills path exposes the Bridge skill", () => {
  assert.equal(existsSync(resolve(skillsPath(), "bridge", "SKILL.md")), true);
});

test("MCP preload is optional and can be disabled", () => {
  assert.equal(mcpBridgeAvailable({ ALLYE_PI_MCP: "0" }), false);
  assert.equal(mcpBridgeAvailable({}), false, "no bridge is registered in the test process");
});

test("unavailable context points at the MCP tools instead of blocking work", () => {
  const state = unavailableStartupContext("network down");
  assert.equal(state.teamSelectionRequired, false);
  assert.equal(state.allyeUnavailable, true);
  assert.match(state.text, /network down/);
  assert.match(state.text, /`initialize`/);
});

test("multi-team initialization requires an explicit team only when none is active", () => {
  const state = inspectTeamSelection("```json\n{\"profile\":{\"teams\":[{\"id\":\"team-a\",\"name\":\"Platform\",\"prefix\":\"PLAT\"},{\"id\":\"team-b\",\"name\":\"Mobile\",\"prefix\":\"MOBI\"}]}}\n```");
  assert.equal(state.teamSelectionRequired, true);
  assert.match(state.text, /team_switch/);
  assert.match(state.text, /Platform \[PLAT\]/);

  const active = inspectTeamSelection("```json\n{\"profile\":{\"teams\":[{\"id\":\"team-a\",\"name\":\"Platform\"},{\"id\":\"team-b\",\"name\":\"Mobile\"}],\"team\":{\"id\":\"team-a\"}}}\n```");
  assert.equal(active.teamSelectionRequired, false);

  assert.equal(inspectTeamSelection("not json").allyeUnavailable, true);
});

test("system sections always carry the bootstrap and keep the team gate on every prompt", () => {
  const gate = inspectTeamSelection("```json\n{\"profile\":{\"teams\":[{\"id\":\"a\",\"name\":\"A\"},{\"id\":\"b\",\"name\":\"B\"}]}}\n```");
  const first = buildSystemSections("BOOT", gate, true);
  const later = buildSystemSections("BOOT", gate, false);
  assert.equal(first.length, 2);
  assert.equal(later.length, 2);
  assert.match(later[1], /allye-team-gate/);

  const ready = { text: "ctx", teamSelectionRequired: false, allyeUnavailable: false, teams: [] };
  assert.deepEqual(buildSystemSections("BOOT", ready, true).map((s) => s.split("\n")[0]), ["<allye-bootstrap>", "<allye-startup-context>"]);
  assert.deepEqual(buildSystemSections("BOOT", ready, false).map((s) => s.split("\n")[0]), ["<allye-bootstrap>"]);
  assert.deepEqual(buildSystemSections("BOOT", ready, true, false).map((s) => s.split("\n")[0]), ["<allye-bootstrap>"]);
});
