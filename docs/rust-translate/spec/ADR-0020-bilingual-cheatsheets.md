# ADR-0020: Cheatsheets are bilingual (FA + EN), split by language

**Status:** Accepted
**Date:** 2026-10-10
**Decides:** How the Komorebi cheatsheets are organised and translated
**Supersedes:** the flat single-language `cheatsheets/*.md` layout

## Context

The cheatsheets serve two audiences at once: they are personal reference
material, and they are published. They were written in Persian only, which serves
one of those audiences.

The project owner's decision was explicit: **both versions must exist**, a
Persian one and an English one.

## Decision

Each cheatsheet exists in two language-specific copies under a language folder:

```
cheatsheets/
  fa/  ... Persian (the originals)
  en/  ... English (the translations)
```

### Rules

1. **The two files are separate documents, not a single bilingual file.** A
   reader opening one gets one language throughout.
2. **They cross-link each other** in the header, so a reader who landed in the
   wrong language is one click from the other.
3. **Hotkeys and commands are copied verbatim, never translated or paraphrased.**
   In a key-binding table the *only* translated cell is the description column;
   the hotkey and command columns are byte-identical between the two files. This
   is what makes the two files refer to the same configuration.
4. **The English file is a translation, not a rewrite.** Section order, table
   rows, callouts, and notes correspond one-to-one. Nothing is added, removed, or
   re-ordered, because the two files must stay diffable against each other.
5. **Dates in the change log keep both calendars.** The originals use the Jalali
   (Shamsi) calendar; the English version converts to Gregorian programmatically
   and notes that the Jalali dates remain authoritative. The conversion table in
   use: `1405/07/09` = 2026-10-01, `1405/07/10` = 2026-10-02,
   `1405/07/11` = 2026-10-03.
6. **The Persian file is the source of truth.** When a binding changes, the
   Persian file is updated first and the English file follows. Not the reverse.

## Scope of this session

Done:

- `fa/komorebi-description.md` ← moved from `cheatsheets/` (13.9 KB)
- `en/komorebi-description.md` ← new translation (11.0 KB)
- `fa/komorebi-hotkeys.md` ← refreshed from the newer dev-tree version at
  `~/projects/komorebi-1click/cheatsheets/komorebi-hotkeys.md` (15.0 KB, 334
  lines, includes section 3.5 `focus-monitor-workspace`, the `Alt + C`/`Alt + V`
  stack bindings, and `wsl.exe`/`notepad++.exe` rows that the older published
  copy did not have)
- `en/komorebi-hotkeys.md` ← new translation (13.5 KB), produced mechanically
  from the Persian file so all 158 binding rows are verbatim-identical

Not done — remaining for a later session, in size order:

| File | Size | Note |
|---|---|---|
| `komorebi-configuration.md` | 61 KB | komorebi.json + whkdrc parameter reference |
| `komorebi-debugging.md` | 91 KB | troubleshooting and diagnostic recipes |
| `Komorebi-Hotkey-Cheatsheet.md` | 59 KB | **deprecated**, carries a redirect header to the four split files; keep as-is, it needs no translation |

The two untranslated files are large reference documents. Translating them is
straightforward but long; they were not attempted at speed, and the two
cheatsheets a reader is most likely to open first (concepts and hotkeys) are
done.

## Consequences

- **A reader gets one language per file, and both languages are available** for
  every cheatsheet that has been converted.
- **The two files stay provably aligned** because only the description column is
  translated; a mechanical check can compare the hotkey and command columns.
- **Publishing and personal use are both served** from the same content, with no
  fork between them.
- **The `cheatsheets/` root still holds `komorebi-configuration.md`,
  `komorebi-debugging.md`, and `Komorebi-Hotkey-Cheatsheet.md`.** They are
  Persian originals awaiting the move to `fa/` alongside their future English
  counterparts; nothing has been deleted.
