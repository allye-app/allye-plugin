# Where test doubles belong

Replace things only at the edges of the system — where your code meets something you do not own or cannot run cheaply and deterministically:

- third-party HTTP APIs and SDKs (payments, email, storage, queues, feature-flag services);
- the clock and randomness;
- the database, only when a real test database (container, in-memory engine, transaction rollback) is not practical in this repo;
- the filesystem or process environment, when the test would otherwise touch real user state.

Do **not** mock:

- your own classes, modules or functions;
- internal collaborators reachable through the public interface;
- anything the codebase owns and can run in the test.

If a test needs a mock of an internal piece to pass, the seam is wrong: move the test up to the public interface.

## Design for testability

Pass external dependencies in instead of constructing them inside the logic. The test can then supply a fake at the boundary without patching modules.

```ts
// Easy to test: the notifier is injected
export async function remindOverdue(
  invoices: InvoiceRepo,
  notifier: { send(to: string, subject: string): Promise<void> },
  now: () => Date,
) {
  for (const inv of await invoices.overdueAt(now())) {
    await notifier.send(inv.ownerEmail, `Invoice ${inv.number} is overdue`);
  }
}

// Hard to test: the dependency and the clock are hidden inside
export async function remindOverdue() {
  const notifier = new SmtpNotifier(process.env.SMTP_URL!);
  for (const inv of await db.invoices.overdueAt(new Date())) {
    await notifier.send(inv.ownerEmail, `Invoice ${inv.number} is overdue`);
  }
}
```

Prefer narrow, purpose-named boundary interfaces over one generic client. A fake for `{ send(to, subject) }` has one obvious shape; a fake for a generic `request(method, url, body)` needs branching in the test setup and hides which external operation the code really performs.

```ts
// Narrow boundary: each operation is explicit and trivially faked
const billingGateway = {
  createCustomer: (email: string) => http.post("/customers", { email }),
  chargeCustomer: (id: string, cents: number) => http.post(`/customers/${id}/charges`, { cents }),
};
```

## In practice

- Reuse the repo's existing fakes, fixtures and helpers before writing new ones.
- A fake records what reached the boundary (the email that would be sent); assert on that outcome, not on how many internal calls produced it.
- Keep doubles honest: return the shapes and errors the real dependency returns, including failures the spec cares about (timeouts, 4xx/5xx, duplicates).
