# 07: Visual system — theme and accent

**What to build:** Dark and Light modes, the eight accent swatches and a custom HEX colour are all
expressed as CSS custom properties consumed by components — no literal colours anywhere. The header's
Toggle Theme and Toggle Color buttons apply instantly and persist across restart. No unconditional
Mica, Acrylic or vibrancy effect exists anywhere in the app.

**Blocked by:** 01 — Scaffold and the first tracer bullet

**Status:** ready-for-agent

- [ ] Both themes render correctly across all eight tabs — a blank or black window (D21) is an automatic failure
- [ ] The selected accent reaches the selected tab, buttons, badges and the header band
- [ ] A custom HEX colour applies and survives restart
- [ ] Toggle Theme and Toggle Color take effect immediately, with no restart, and persist
- [ ] No component contains a literal colour value; every colour resolves from a token
- [ ] No unconditional Mica, Acrylic or vibrancy effect is present
