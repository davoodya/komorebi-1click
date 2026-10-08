# 08: Typography and UI scale

**What to build:** The app font family list is a fast tiered standard list whose last entry is
`Custom (All Fonts)...`; choosing it enumerates the full installed set once, off the UI thread, and
caches the result. The console font list contains only monospaced families and gets the same
sentinel. App font size, console size and UI scale (100/125/150%) preview live as you change them and
persist only when applied.

**Blocked by:** 07 — Visual system — theme and accent

**Status:** ready-for-agent

- [ ] The standard font list opens instantly — enumerating fonts never stalls opening the list
- [ ] The sentinel entry never remains selected as the applied value
- [ ] Full enumeration runs off the UI thread, happens once, and is cached for later opens
- [ ] The console font list contains only monospaced families
- [ ] Changing family, size or scale previews immediately without touching persisted settings
- [ ] Applying persists every typography control across restart
- [ ] 125% scale verified visually on the portrait monitor with no clipped, overlapping or overflowing layout
