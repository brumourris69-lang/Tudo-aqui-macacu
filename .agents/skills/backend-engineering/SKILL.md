---
name: backend-engineering
description: Use when changing trusted server code, API contracts, background processing, data consistency, retries, idempotency, or backend observability; load provider-specific skills for Firebase or Supabase details.
---

# Backend Engineering

- Identify the authoritative data source, caller identity, authorization boundary, and public/private fields before changing a handler.
- Validate inputs at the boundary and make error contracts stable without exposing internal details.
- For retries or asynchronous work, define idempotency keys, ordering/version rules, timeout, cancellation, dead-letter behavior, and recovery.
- Use least privilege and server-side authorization. Keep privileged keys out of clients, fixtures, and logs.
- Bound queries and batches, account for concurrency and partial failure, and document operational signals.
- Test success, invalid input, denied authorization, dependency outage, replay, and concurrency at the layer that provides the guarantee.
