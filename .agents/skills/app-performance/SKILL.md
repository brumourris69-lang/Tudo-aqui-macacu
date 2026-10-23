---
name: app-performance
description: Use when investigating startup, rendering, memory, battery, network, database, or backend latency and when a change needs measurable performance validation.
---

# App Performance

- Define the user-visible symptom and a measurable baseline before optimizing.
- Use the appropriate profiler or trace on a representative device/build mode; do not infer runtime performance from source inspection alone.
- Distinguish UI-thread work, rebuild/layout cost, image/memory pressure, network latency, database query cost, and backend saturation.
- Prefer profiling evidence and targeted fixes over speculative caching, premature concurrency, or broad rewrites.
- Re-measure after the change and check correctness, memory, battery, and accessibility trade-offs.
- State device, build mode, sample size, and environmental limitations; never present a single local measurement as a general guarantee.
