---
name: allye-tdd-workflow
description: Test-Driven Development discipline for AI agents. Red-Green-Refactor cycle, detection heuristic, and anti-patterns. Use when implementing features or fixing bugs.
version: "1.0"
category: methodology
---

# TDD Workflow

This skill defines the Test-Driven Development discipline for implementing code with Allye workflows. TDD is not about writing tests — it's about **designing code through tests**.

---

## 1. TDD Detection Heuristic

Before implementing anything, ask yourself:

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

### Red — Write a Failing Test

Write a test that describes the behavior you want:

```javascript
// Good: tests WHAT, not HOW
test("should return 404 when user not found", async () => {
  const response = await request(app).get("/users/nonexistent");
  expect(response.status).toBe(404);
  expect(response.body.error).toBe("User not found");
});
```

```python
# Good: tests behavior, not implementation
def test_calculate_discount_for_premium_user():
    user = User(tier="premium")
    order = Order(total=100.00)
    assert calculate_discount(user, order) == 15.00
```

**Run the test. It MUST fail.** If it passes:
- The functionality already exists — don't reimplement it
- The test is wrong — it's not testing what you think

### Green — Make It Pass

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

### Refactor — Clean Up

With green tests as your safety net:

- Remove duplication
- Improve naming
- Simplify logic
- Extract functions if the code is too long
- Apply patterns where they genuinely help

**Run tests after EVERY change.** If a test fails, you broke something — undo and try again.

### Repeat

Write the next test for the next behavior. Continue the cycle until all acceptance criteria are met.

---

## 3. Test Quality Guidelines

### Write tests that describe behavior

```javascript
// Bad: tests implementation details
test("should call userRepository.findById", () => { ... });

// Good: tests observable behavior
test("should return user profile for valid ID", () => { ... });
```

### One assertion per concept

```python
# Bad: testing multiple unrelated things
def test_user_creation():
    user = create_user("alice", "alice@example.com")
    assert user.name == "alice"
    assert user.email == "alice@example.com"
    assert user.created_at is not None
    assert send_welcome_email.called  # different concern!

# Good: separate tests for separate concepts
def test_user_created_with_correct_fields():
    user = create_user("alice", "alice@example.com")
    assert user.name == "alice"
    assert user.email == "alice@example.com"

def test_welcome_email_sent_on_creation():
    create_user("alice", "alice@example.com")
    assert send_welcome_email.called
```

### Test edge cases

After the happy path passes, add tests for:
- Empty inputs
- Invalid inputs
- Boundary values
- Error conditions
- Concurrent access (if applicable)

### Name tests clearly

The test name should read like a specification:
- `should return empty list when no users match filter`
- `should throw validation error when email is invalid`
- `should retry request up to 3 times on timeout`

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

### Arrange-Act-Assert (AAA)

```javascript
test("should apply discount to order total", () => {
  // Arrange
  const order = createOrder({ total: 100, coupon: "SAVE10" });

  // Act
  const result = applyDiscount(order);

  // Assert
  expect(result.total).toBe(90);
});
```

### Test doubles hierarchy

Use the simplest double that works:

| Double | When to use |
|--------|-------------|
| **Stub** | Return a fixed value. Use for dependencies whose output you control. |
| **Spy** | Verify a call was made. Use when the side effect matters. |
| **Mock** | Set expectations upfront. Use sparingly — prefer stubs + assertions. |
| **Fake** | Lightweight implementation (e.g., in-memory DB). Use for integration tests. |

### Boundary testing

Test at the edges of your system, not in the middle:

```
[External Input] → [Your Boundary] → [Your Logic] → [Your Boundary] → [External Output]
     ↑                    ↑                                  ↑
  Validate here     Test here                          Test here
```

---

## 6. When the Cycle Feels Wrong

| Feeling | Likely cause | Fix |
|---------|-------------|-----|
| "I can't write a test first" | You don't understand the requirements yet | Go back to the task description. Clarify with the user. |
| "The test is too complex" | The function does too much | Break the function into smaller pieces. Test each piece. |
| "I need to test private methods" | The public interface is too coarse | Refactor to expose behavior through the public API. |
| "Tests are slow" | Too many integration tests, not enough unit tests | Apply the test pyramid: many unit, some integration, few E2E. |
| "Tests break when I refactor" | Tests are coupled to implementation | Rewrite tests to assert on behavior, not implementation details. |
