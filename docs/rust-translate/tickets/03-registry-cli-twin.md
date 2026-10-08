# 03: Registry completeness and the CLI twin

**What to build:** All 28 verbs live in one registry carrying tab, description, script reference,
read-only and admin flags, and CLI help text. The CLI twin dispatches them headlessly, generates
`--help` from the registry, and returns the complete exit-code contract. This makes the command line
a full alternate surface over the same code path the GUI will use, which is also the project's primary
test seam.

**Blocked by:** 01 — Scaffold and the first tracer bullet

**Status:** ready-for-agent

- [ ] All 28 verbs are registered, each grouped under exactly one of the eight tabs
- [ ] Every declared verb resolves to an existing script file; no verb leaves the registry to find its script
- [ ] `--help` is generated from the registry and lists exactly the registered set, with help text and category headers — there is no second hand-maintained copy
- [ ] Every verb dispatches headlessly with exit 0, the script's own code, 2 on parse failure, or 127 on a missing script
- [ ] An unknown verb or malformed arguments print usage on stderr and exit 2
- [ ] Adding a verb requires one registry entry and nothing else (the extension rule holds)
- [ ] Read-only and admin flags are exposed on every verb so later tickets can gate on them
