---
name: sandbox
description: Open-ended ideation and research before committing to scope. Use when the user has a vague goal and wants to think out loud, explore directions, or research before defining what to build — not yet ready for Product Planning's Epic/Feature/Story structure.
version: "1.2"
category: methodology
---

# Sandbox / Discovery

This is the entry point for ideas that aren't ready to become work items yet. Use it when the user wants to explore, not commit — Product Planning already assumes a direction has been chosen; this skill is where that direction gets found.

<!-- adapted from superpowers:brainstorming (MIT) -->
<HARD-GATE>
Do not create any Allye work item, and do not treat any direction as decided, until the user has explicitly approved it. This skill's only output is a Discovery Doc and a handover — never an Epic, Feature, or Story. If you catch yourself about to call `work_create`, stop: that's Product Planning's job, one conversation later.
</HARD-GATE>

## 1. The core rule: ask, don't decide

You never unilaterally pick a direction. When there's a fork, ask — one focused question at a time, never several forks stacked into one message. When you have a view, say so and explain why, but frame it as a recommendation the user can redirect, not a decision you've already made. (For *how* to ask — prose vs. the `AskUserQuestion` tool — see `using-allye`'s "Asking Questions" section; it's a global rule, not repeated here.)

<!-- adapted from superpowers:brainstorming (MIT) — anti-rationalization table -->
### Red flags — these thoughts mean stop and ask instead

| Thought | Reality |
|---|---|
| "This is obviously what they want" | Obvious to you isn't the same as confirmed. Ask. |
| "I'll just explore this direction and show them" | Exploring silently is still deciding silently — narrate the fork before you go down it. |
| "We've been going back and forth a lot, let me just pick" | Fatigue isn't consent. If the user wants you to decide, they'll say so — that's a valid answer to a question, not a reason to stop asking. |
| "This detail is too small to ask about" | Small decisions compound. If it would surprise the user later, it's worth a quick check now. |

### When it's fine to just proceed

<!-- adapted from trailofbits/skills ask-questions-if-underspecified (CC-BY-SA-4.0) — adapted as a rubric, not their original text -->
Not every gap needs a question. Ask when the answer would change *what* gets built or *which direction* gets explored. Don't ask when:
- The gap is a well-established default with no real controversy — state the assumption instead of asking about it
- The user already answered a broader version of the question and this is a narrower instance of the same answer
- Asking would just be confirming something the user's own message already made unambiguous

## 2. Research (optional, user-triggered, parallel is fine)

If the direction needs facts to evaluate — how a technology actually works, what a public repo actually does, what the current landscape looks like — offer to research before continuing the discussion, rather than reasoning from assumption.

- **Web research** → dispatch the `deep-search` agent (`Agent` tool) with a single, explicit objective. It's bounded and doesn't need to ask you anything mid-task, which is what makes it safe to dispatch.
- **Public repo analysis** → dispatch the `code-analyzer` agent (`Agent` tool) with the repo URL, a specific objective, and the session scratchpad path (it only clones under that path, and will refuse to fall back to `/tmp` if you omit it). It reads thoroughly, reports, and deletes the clone unconditionally — you never touch the clone yourself.

Both can run in parallel if you need both kinds of research at once — dispatch them in the same turn.

<!-- adapted from humanlayer/humanlayer research_codebase (Apache-2.0) -->
**Keep research and direction-setting separate.** A research agent documents what exists — it does not recommend what to do about it. When findings come back, bring them into the conversation and let the user (with your input) decide what they mean for the direction — don't let a research agent's report silently become the decision.

## 3. Exit: the Discovery Doc

When a direction is approved — explicitly, by the user, not inferred — synthesize the conversation into a Discovery Doc:

1. **What goes in it:** the approved direction and why; paths that were explored and rejected, with the reason (the next phase should never accidentally re-propose something already ruled out); research findings, if any, with their sources; prototypes, if any.
2. **Where it goes:** call `doc_full_tree` first. Propose a parent location based on what you see — don't guess blindly and don't default to the root. Get the user's explicit confirmation of placement before creating anything.
3. **Create it:** `doc_create` (type `guide` or `page`, needs an emoji).
4. **Hand off:** emit a `discovery-to-planning` handover — see the `handover-protocol` skill for the shared marker format, and its `references/discovery-to-planning.md` for this handover's specific template. Reference the Discovery Doc; don't duplicate its content into the handover.

## 4. What this skill is not

This is not Technical Planning — no stack decisions, no architecture, no tasks here. It is not Product Planning — no Epic/Feature/Story structure gets created here (see the HARD-GATE above). If the user arrives already knowing exactly what they want and just needs it turned into work items, route to `product-planning` directly instead — Sandbox isn't the right entry point for that.
