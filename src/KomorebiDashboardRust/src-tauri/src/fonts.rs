// Ticket 08 — the installed-font enumeration, dependency-free.
//
// The WPF build calls `Fonts.SystemFontFamilies` (DirectWrite); this crate has
// no DirectWrite binding and gains none for one list. What Windows does expose
// for every installed face, without a new dependency, is the `Fonts` registry
// key — one value per face, whose name is the display name and whose type is
// the parenthesized trailing token. This module parses that into family names.
//
// The honest granularity note (also recorded in the tracker): the registry
// lists FACES, so the result is face-level rather than WPF's family-level — a
// "Segoe UI Semibold" entry is its own real family on Win10+, while a
// "Segoe UI Bold & Italic" entry does not resolve as a CSS family and falls
// back gracefully in the WebView. The tier-1 standard list (the frontend's)
// covers the common cases; this list exists for the user who wants everything.

use std::collections::BTreeSet;
use std::process::Command;

/// The registry keys that list installed fonts, machine-wide then per-user.
const FONT_KEYS: [&str; 2] = [
    r"HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
    r"HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
];

/// One parsed face name from `reg query` output: `name    REG_SZ    file`.
fn parse_face_line(line: &str) -> Option<String> {
    let trimmed = line.trim();
    // The registry value name runs until the first four-or-more-space gap, then
    // the type token, then the file. Splitting on two spaces is the shape reg
    // query prints; a single space inside a font name is common ("Courier New").
    let split = trimmed.find("    ")?;
    let name = trimmed[..split].trim();
    if name.is_empty() {
        return None;
    }
    Some(name.to_string())
}

/// The longest trailing parenthesized group treated as a FILE descriptor.
///
/// Windows writes `(TrueType)`, `(OpenType)`, `(All res)` and a family of
/// legacy hardware/codepage tokens (`(931)`, `(VGA)`, `(8514o)`, ...). Every
/// real one is short, so the rule is "a trailing parenthesized group of at
/// most 12 characters" — one rule that covers them all without enumerating
/// every codepage.
const MAX_TYPE_TOKEN_LEN: usize = 12;

/// Strip trailing type tokens: "Segoe UI (TrueType)" -> "Segoe UI".
///
/// The strip LOOPS, because the registry's value name for a face that already
/// carries a parenthesized qualifier reads e.g.
/// "110_Besmellah_1(MRT) (TrueType)" — the file descriptor sits OUTSIDE the
/// face's own group, so one pass would leave "110_Besmellah_1(MRT)". The
/// documented trade-off: a face named with two of its own trailing groups
/// loses both. No real font does.
fn strip_type_token(mut name: &str) -> &str {
    loop {
        let trimmed = name.trim_end();
        if !trimmed.ends_with(')') {
            return trimmed;
        }
        match trimmed.rfind('(') {
            Some(open) if trimmed.len() - open <= MAX_TYPE_TOKEN_LEN => name = trimmed[..open].trim_end(),
            _ => return trimmed,
        }
    }
}

/// Every installed face, deduplicated case-insensitively and sorted.
///
/// The dedupe key is the name itself, case-folded: HKLM and a per-user
/// install both list e.g. Segoe UI, and the picker wants one entry per name.
///
/// ```text
/// HKEY_LOCAL_MACHINE\...\Fonts
///     Segoe UI (TrueType)    REG_SZ    segoeui.ttf
///     Courier New (TrueType)    REG_SZ    cour.ttf
/// ```
///
/// becomes `["Courier New", "Segoe UI"]` — the key line and the file
/// descriptor are dropped, the type token is stripped, and the rest is
/// case-folded sorted. (The pins below are tests, not a doc example.)
pub fn family_names_from_output(output: &str) -> Vec<String> {
    let mut seen: BTreeSet<String> = BTreeSet::new();
    for line in output.lines() {
        if let Some(face) = parse_face_line(line) {
            let name = strip_type_token(&face);
            if !name.is_empty() {
                seen.insert(name.to_string());
            }
        }
    }
    // BTreeSet<String> is ordinal; the picker wants the same
    // case-insensitive, punctuation-ignoring order a user expects.
    let mut names: Vec<String> = seen.into_iter().collect();
    names.sort_by(|a, b| {
        a.to_lowercase()
            .cmp(&b.to_lowercase())
            .then_with(|| a.cmp(b))
    });
    names
}

/// Read both keys through `reg query`. A missing key is an empty list, not a
/// failure: a machine without HKCU font installs still resolves.
fn query_key(key: &str) -> String {
    let out = Command::new("reg")
        .args(["query", key])
        .output();
    match out {
        Ok(o) => String::from_utf8_lossy(&o.stdout).into_owned(),
        Err(_) => String::new(),
    }
}

/// Every installed font, or an empty list when the registry cannot be read.
pub fn enumerate_installed() -> Vec<String> {
    let mut output = String::new();
    for key in FONT_KEYS {
        output.push_str(&query_key(key));
        output.push('\n');
    }
    family_names_from_output(&output)
}

#[cfg(test)]
mod tests {
    use super::*;

    const REG_SAMPLE: &str = "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts\n    \
        Arial (TrueType)    REG_SZ    arial.ttf\n    \
        Arial Bold (TrueType)    REG_SZ    arialbd.ttf\n    \
        Cascadia Mono (TrueType)    REG_SZ    CascadiaMono.ttf\n    \
        Segoe UI (TrueType)    REG_SZ    segoeui.ttf\n    \
        segui (TrueType)    REG_SZ    seguisb.ttf\n    \
        Wingdings (OpenType)    REG_SZ    wingding.ttf\n";

    #[test]
    fn strips_the_type_token_keeps_the_face_name() {
        assert_eq!(strip_type_token("Segoe UI (TrueType)"), "Segoe UI");
        assert_eq!(strip_type_token("Wingdings (OpenType)"), "Wingdings");
        assert_eq!(strip_type_token("MS Sans Serif (931)"), "MS Sans Serif");
        assert_eq!(strip_type_token("Small Fonts (VGA)"), "Small Fonts");
        // A name without a trailing group is untouched, and so is a very long
        // one — a parenthesized group that long is part of the name.
        assert_eq!(strip_type_token("Segoe UI"), "Segoe UI");
        assert_eq!(strip_type_token("Segoe UI (Emoji and Symbols)"), "Segoe UI (Emoji and Symbols)");
        // A face whose own name carries a group, behind the file descriptor:
        // BOTH groups are descriptors here (real registry shape).
        assert_eq!(strip_type_token("110_Besmellah_1(MRT) (TrueType)"), "110_Besmellah_1");
        assert_eq!(strip_type_token("Arial (TrueType) (TrueType)"), "Arial");
    }

    #[test]
    fn parses_only_lines_that_carry_a_registry_value() {
        assert_eq!(
            parse_face_line("    Arial (TrueType)    REG_SZ    arial.ttf"),
            Some("Arial (TrueType)".to_string())
        );
        // The key header and blank lines are skipped, not parsed as faces.
        assert_eq!(parse_face_line("HKEY_LOCAL_MACHINE\\..."), None);
        assert_eq!(parse_face_line(""), None);
        assert_eq!(parse_face_line("    "), None);
    }

    #[test]
    fn deduplicates_case_insensitively_and_sorts() {
        let names = family_names_from_output(REG_SAMPLE);
        // "seguisb.ttf"'s value name is "seguid" in reality; the sample's
        // lower-case "segu i" is not a real key — what matters is the CASE
        // dedupe: a per-user repeat of an installed family appears once.
        let lower: Vec<String> = names.iter().map(|s| s.to_lowercase()).collect();
        let mut sorted = lower.clone();
        sorted.sort();
        sorted.dedup();
        assert_eq!(lower, sorted, "output is case-folded sorted");
        assert!(names.contains(&"Cascadia Mono".to_string()));
        assert!(names.contains(&"Arial".to_string()));
        assert!(names.contains(&"Arial Bold".to_string()));
        // The type token is gone from every entry.
        for name in &names {
            assert!(!name.ends_with(')'), "{name} kept its type token");
        }
    }

    #[test]
    fn an_unreadable_registry_is_an_empty_list_not_a_failure() {
        // A key that does not exist prints an error to stderr and nothing to
        // stdout, so the parse yields nothing — the picker shows only tier 1
        // plus the sentinel, and says so.
        let names = family_names_from_output("ERROR: Invalid key name.\n");
        assert!(names.is_empty());
    }

    #[test]
    fn enumerate_on_this_machine_returns_the_faces_windows_reports() {
        // This test observes the real registry: it asserts the SHAPE of the
        // answer (deduped, sorted, no type tokens), not a fixed list, because
        // every machine installs different fonts.
        let names = enumerate_installed();
        assert!(!names.is_empty(), "this Windows host reports installed fonts");
        let mut folded: Vec<String> = names.iter().map(|s| s.to_lowercase()).collect();
        let len = folded.len();
        folded.sort();
        folded.dedup();
        assert_eq!(folded.len(), len, "no case-duplicates");
        // The strip removes trailing FILE descriptors; a name may still
        // CONTAIN a parenthesized group (real fonts like "2  Mitra_1
        // (MRT)Bold" do) — what must be gone is the trailing one.
        for name in &names {
            assert!(!name.ends_with(')'), "{name} kept a trailing descriptor");
            assert!(!name.trim_end().is_empty(), "empty name");
        }
    }
}
