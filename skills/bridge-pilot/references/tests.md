# Good and bad tests

A good test checks something a caller cares about, uses only the public interface, keeps passing when internals change, and makes one logical claim. The examples use TypeScript with a Vitest/Jest-style API; apply the same ideas in the repo's own language and framework.

## Behavior through the public interface

```ts
// Good: states what the caller sees
test("an expired invite cannot be accepted", async () => {
  const clock = fixedClock("2026-03-10T12:00:00Z");
  const invites = createInviteService({ clock, store: inMemoryInviteStore() });
  const invite = await invites.issue({ email: "ana@example.com", ttlHours: 24 });

  clock.advanceHours(25);

  await expect(invites.accept(invite.token)).rejects.toThrow("invite expired");
});
```

It drives the real service, controls only the clock (a system boundary), and would still pass if the expiry check moved to another module.

## Coupled to the implementation

```ts
// Bad: asserts how the code works, not what it does
test("accept calls isExpired with the invite", async () => {
  const spy = vi.spyOn(inviteRules, "isExpired");
  await invites.accept(token);
  expect(spy).toHaveBeenCalledWith(expect.objectContaining({ token }));
});
```

Warning signs: a spy or mock on your own module, a private helper under test, call counts or order treated as behavior, a name that describes mechanics. Rewrite it at the seam:

```ts
test("a fresh invite can be accepted once", async () => {
  const invite = await invites.issue({ email: "ana@example.com", ttlHours: 24 });
  await invites.accept(invite.token);
  await expect(invites.accept(invite.token)).rejects.toThrow("invite already used");
});
```

## Tautological expectations

```ts
// Bad: the expectation repeats the implementation's formula
const expected = Math.round(subtotal * (1 + TAX_RATE) * 100) / 100;
expect(totalWithTax(subtotal)).toBe(expected);

// Good: a worked example someone can check by hand
expect(totalWithTax(200)).toBe(246); // 23% tax
```

## Would it catch the bug?

Before calling a test done, name the plausible defect it protects against (off-by-one at the expiry boundary, missing permission check, duplicate submit) and check that the test fails if that defect is introduced. A test that passes against a broken implementation is worse than none, because it reports false safety.

## Edge cases and errors

Cover the boundaries the spec names (`[AC-NN]` error scenarios, limits, empty input, permission denied) at the same seam. One error path per test; assert on the observable outcome (status code, error message, unchanged state), not on internal logging.
