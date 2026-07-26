---
name: tdd-workflow
description: Test-Driven Development discipline for AI agents. Red-Green-Refactor cycle, detection heuristic, and anti-patterns. Use when implementing features or fixing bugs.
version: "1.1"
category: methodology
---

# TDD Workflow

TDD is not about writing tests — it's about **designing code through tests**.

---

## 1. TDD Detection Heuristic

Before implementing anything, ask:

> **Can I write `expect(fn(input)).toBe(output)` before writing `fn`?**

- **Yes** → TDD is mandatory. Follow Red → Green → Refactor.
- **No** → Write tests after implementation, but always write tests.

### When TDD applies (test first)

- Pure functions and business logic
- Data transformations and parsing
- Validation rules
- API endpoint behavior
- Database queries and mutations
- State management logic
- Utility functions
- Algorithm implementations

### When TDD doesn't apply (test after)

- UI layout and styling
- Infrastructure and configuration
- Third-party integrations (mock boundaries, test your adapter)
- File system operations
- Environment setup scripts
- One-off data migrations

<EXTREMELY_IMPORTANT>
Even when TDD doesn't apply, you MUST still write tests.
The only question is whether the test comes before or after the implementation.
"No tests needed" is never an acceptable answer.
</EXTREMELY_IMPORTANT>

---

## 2. The Red-Green-Refactor Cycle

### Red — write a failing test

Write a test that describes the target behavior, not the implementation:

```javascript
test("should return 404 when user not found", async () => {
  const response = await request(app).get("/users/nonexistent");
  expect(response.status).toBe(404);
  expect(response.body.error).toBe("User not found");
});
```

**Run the test. It MUST fail.** If it passes, either the functionality already exists (don't reimplement it) or the test is wrong (it's not testing what you think).

### Green — make it pass

Write the **minimum code** to make the test pass:

<HARD-GATE>
Rules for the Green phase:
1. Do NOT add features the test doesn't require
2. Do NOT optimize prematurely
3. Do NOT handle edge cases not covered by tests — write more tests first
4. Do NOT refactor during Green — that's the next phase
5. It's OK if the code is ugly — Green is about correctness, not beauty
</HARD-GATE>

**Run the test. It MUST pass.**

### Refactor — clean up

With green tests as your safety net: remove duplication, improve naming, simplify logic, extract functions where the code is too long, apply patterns where they genuinely help.

**Run tests after EVERY change.** A failing test means you broke something — undo and try again.

### Repeat

Write the next test for the next behavior. Continue the cycle until all acceptance criteria are met.

---

## 3. Test Quality

- **Assert on behavior, not implementation** — `should return user profile for valid ID`, not `should call userRepository.findById`. Tests coupled to implementation break on every refactor.
- **One assertion per concept.** A test that checks unrelated things (fields set *and* an email was sent) hides which concept broke when it fails — split into separate tests.
- **Cover the edges** after the happy path passes: empty inputs, invalid inputs, boundary values, error conditions, concurrent access where applicable.
- **Name tests as specifications** — `should throw validation error when email is invalid`, `should retry request up to 3 times on timeout`.

---

## 4. Rules — Non-Negotiable

<HARD-GATE>
1. **Never delete a failing test.** If a test fails, either fix the code or fix the test — but understand WHY it fails first. Deleting tests hides bugs.

2. **Never suppress type errors.** No `@ts-ignore`, no `# type: ignore`, no `as any`. Type errors are bugs caught early. Fix them.

3. **Never commit with failing tests.** All tests must pass before a task is marked as done. No exceptions.

4. **Never mock what you don't own.** Mock your adapters, not third-party libraries directly. If the library changes, your mock won't catch it.

5. **Tests must be deterministic.** No flaky tests. No tests that depend on time, network, or random values without controlling them.
</HARD-GATE>

---

## 5. Testing Patterns

Structure each test **Arrange-Act-Assert**: set up state, perform the one action under test, assert the result.

Use the simplest test double that works:

| Double | When to use |
|--------|-------------|
| **Stub** | Return a fixed value. Use for dependencies whose output you control. |
| **Spy** | Verify a call was made. Use when the side effect matters. |
| **Mock** | Set expectations upfront. Use sparingly — prefer stubs + assertions. |
| **Fake** | Lightweight implementation (e.g., in-memory DB). Use for integration tests. |

Test at your system's boundaries — validate at the input boundary, assert at the output boundary — rather than reaching into the middle.

---

## 6. When the Cycle Feels Wrong

| Feeling | Likely cause | Fix |
|---------|-------------|-----|
| "I can't write a test first" | You don't understand the requirements yet | Go back to the task description. Clarify with the user. |
| "The test is too complex" | The function does too much | Break the function into smaller pieces. Test each piece. |
| "I need to test private methods" | The public interface is too coarse | Refactor to expose behavior through the public API. |
| "Tests are slow" | Too many integration tests, not enough unit tests | Apply the test pyramid: many unit, some integration, few E2E. |
| "Tests break when I refactor" | Tests are coupled to implementation | Rewrite tests to assert on behavior, not implementation details. |
