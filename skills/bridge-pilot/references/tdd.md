# Test-first, one behavior at a time

The red → green loop exists to produce tests worth keeping: tests that describe what a caller observes, survive refactoring, and would catch a plausible bug. This page is how the Pilot runs it.

## The seam

A seam is the public boundary where a behavior can be observed without reaching inside: an HTTP endpoint, an exported function, a CLI invocation, a component's rendered output, an emitted event.

- Use the seam the Strategist declared for the slice. If it is clear from the task and the repo's patterns, do not ask again.
- If no usable seam exists, return `blocked` with the smallest seam you would propose; the Mothership decides.
- Prefer the highest seam that still gives fast, reliable feedback. Coverage of everything is not the goal; effort goes to critical paths and non-trivial rules.

Read local conventions first (domain glossary, ADRs, existing tests near the code) so names and interfaces match the codebase.

## The loop

1. Pick one small behavior at the seam.
2. Write one test that states it from the caller's point of view.
3. Run only that test. It must fail, and for the reason you expect (an assertion about the missing behavior — not an import error, typo or broken fixture). Record the command and failure line.
4. Write the least code that makes it pass.
5. Run it again; record green. Run the slice's other declared tests to make sure nothing nearby broke.
6. Let what you learned choose the next behavior.

Rules:

- red before green, always observed, never assumed;
- one behavior, one test, one minimal change per cycle;
- no speculative features and no tests for behaviors the slice does not need;
- structural refactoring waits until the behavior is covered and stays within the slice;
- test names say what happens, not how the code does it.

## Anti-patterns

- **Coupled to the implementation.** Mocks of your own modules, assertions on private methods, call counts or internal ordering. These break when the code is reorganized but the behavior is unchanged.
- **Tautological.** The expected value is computed with the same logic as the code under test, so the test can never disagree with it. Use a known, independently worked-out example.
- **Horizontal slicing.** Writing every test first and all the code afterwards. It locks in an imagined design before any feedback; work vertically, one behavior at a time.

## When not to use the loop

Docs, configuration, renames, generated files and other changes without executable behavior do not get artificial tests. Use the validation the Strategist declared (build, type check, lint, schema check) and report it under `validation`.

More: `tests.md` (good and bad tests), `mocking.md` (where test doubles belong).
