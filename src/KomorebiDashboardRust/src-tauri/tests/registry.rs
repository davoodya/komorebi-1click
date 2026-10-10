//! Ticket 03 — registry completeness and the extension rule.
//!
//! Everything here is derived from the table itself rather than from a number
//! written in a document. That is the point: the project's documents said "28
//! verbs" for weeks while the shipping table carried 35, because the number was
//! copied forward and never re-derived. A count that a test computes cannot
//! drift that way, and a count that a test prints can be checked against the
//! prose instead of believed.
//!
//! Each assertion is written against externally observable facts — the names,
//! the tabs, whether a script exists — and never against the table's internal
//! shape, so a row can be added or a field renamed without making these lie.

use dashboard_core::registry::{self, Verb, TABS};
use std::collections::{BTreeMap, BTreeSet};
use std::path::{Path, PathBuf};

fn scripts() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../scripts")
}

/// Machine-readable evidence line. `tests/rust-ticket03-probe.ps1` parses these
/// out of `cargo test -- --nocapture`, so every count in the ticket's evidence is
/// a number the test that owns it printed, not one typed by hand.
fn probe(field: &str, value: impl std::fmt::Display) {
    println!("[probe] {field}={value}");
}

#[test]
fn every_registered_verb_resolves_to_an_existing_script() {
    let dir = scripts();
    let mut missing = Vec::new();
    for verb in registry::registry() {
        if !dir.join(verb.script).is_file() {
            missing.push(format!("{} -> {}", verb.verb, verb.script));
        }
    }
    assert!(
        missing.is_empty(),
        "a registry row must not leave the registry to find its script; missing: {missing:?}"
    );
    probe("verbs", registry::registry().len());
    probe(
        "distinct_scripts",
        registry::registry()
            .iter()
            .map(|v| v.script)
            .collect::<BTreeSet<_>>()
            .len(),
    );
}

#[test]
fn verb_names_are_unique_and_grouped_under_exactly_one_tab() {
    let verbs = registry::registry();
    let names: BTreeSet<&str> = verbs.iter().map(|v| v.verb).collect();
    assert_eq!(
        names.len(),
        verbs.len(),
        "two rows claim the same verb name, so one would be unreachable"
    );

    let tab_ids: BTreeSet<&str> = TABS.iter().map(|t| t.id).collect();
    for verb in verbs {
        assert!(
            tab_ids.contains(verb.tab),
            "'{}' is grouped under '{}', which is not a declared tab — a row in an \
             unknown group is a row no tab renders",
            verb.verb,
            verb.tab
        );
    }
    // Exactly one group per verb is what the map key proves; the count is here so
    // the evidence records the grouping rather than only asserting it.
    let per_tab: BTreeMap<&str, usize> = TABS
        .iter()
        .map(|t| (t.id, registry::verbs_in_tab(t.id).count()))
        .collect();
    probe(
        "tabs_with_verbs",
        per_tab.values().filter(|count| **count > 0).count(),
    );
    for (tab, count) in per_tab {
        probe(&format!("tab_{tab}"), count);
    }
}

#[test]
fn the_gui_rows_and_the_cli_only_rows_agree_with_the_table() {
    let verbs = registry::registry();
    let rows = verbs.iter().filter(|v| v.has_row()).count();
    let suppressed: Vec<&str> = verbs
        .iter()
        .filter(|v| !v.has_row())
        .map(|v| v.verb)
        .collect();

    // A suppressed row must be *reachable* — either the registry has a more
    // specific row that supersedes it, or the CLI stores the two-part spelling.
    // Suppressing a verb with no replacement would delete a feature while
    // leaving it in the table, which reads as "present" everywhere but the GUI.
    for verb in &suppressed {
        let reachable = registry::registry()
            .iter()
            .any(|other| other.verb != *verb && other.verb.starts_with(verb));
        assert!(
            reachable,
            "'{verb}' has no row of its own and no more specific row supersedes it, \
             so nothing can dispatch it from the window"
        );
    }

    assert_eq!(rows, 31, "rendered GUI rows");
    assert_eq!(suppressed.len(), 4, "CLI-only rows: {suppressed:?}");
    probe("gui_rows", rows);
    probe("cli_only_rows", suppressed.len());
    probe("cli_only_names", suppressed.join(","));
}

#[test]
fn read_only_and_admin_flags_are_exposed_on_every_verb() {
    let verbs = registry::registry();
    let readonly: Vec<&str> = verbs
        .iter()
        .filter(|v| v.is_read_only)
        .map(|v| v.verb)
        .collect();
    let admin: Vec<&str> = registry::admin_verbs().map(|v| v.verb).collect();

    // Read-only means "changes nothing on the system", so an administrative verb
    // can never be one: needing Administrator to change nothing would be a
    // contradiction, and it would badge a destructive row as harmless.
    for verb in &readonly {
        assert!(
            !registry::find(verb).unwrap().requires_admin,
            "'{verb}' is both read-only and administrative"
        );
    }
    // The 6 read-only verbs are exactly the diagnostics. If a seventh appears,
    // it must be a deliberate decision rather than an accidental flag.
    assert_eq!(readonly.len(), 6, "read-only verbs: {readonly:?}");
    assert_eq!(admin.len(), 10, "admin verbs: {admin:?}");
    probe("read_only_verbs", readonly.len());
    probe("read_only_names", readonly.join(","));
    probe("admin_verbs", admin.len());
    probe("admin_names", admin.join(","));
}

#[test]
fn status_is_registered_and_cannot_be_talked_into_administrative_work() {
    let status = registry::find("status").expect("status is a shipped verb");
    assert!(status.is_read_only);
    assert!(!status.requires_admin);
    // It carries the health action as a FIXED argument, which is the mechanism
    // that stops a caller naming a different one: the shape declares no value, so
    // `run` refuses any user argument at all.
    assert_eq!(status.fixed_arguments, ["-Action", "status"]);
    assert!(
        !status.accepts_user_arguments(),
        "status declares no value in its shape, so nothing may be forwarded to it"
    );
}

#[test]
fn help_is_generated_from_the_table_and_lists_exactly_the_registered_set() {
    let help = registry::build_help();
    for verb in registry::registry() {
        assert!(
            help.contains(verb.verb),
            "'{}' is registered but missing from --help, so the two lists disagree",
            verb.verb
        );
        assert!(
            help.contains(verb.help),
            "'{}' appears in help without its own help text",
            verb.verb
        );
    }
    // Grouped by tab, and only tabs that carry verbs get a heading — an empty
    // heading reads as "this tab is broken" rather than "this tab has no verbs".
    for tab in TABS {
        let carries_verbs = registry::verbs_in_tab(tab.id).count() > 0;
        assert_eq!(
            help.contains(&format!("  {}:", tab.label)),
            carries_verbs,
            "help heading for '{}' should exist exactly when it has verbs",
            tab.label
        );
    }
    // The administrative marker is what tells a CLI user why a verb will refuse.
    for verb in registry::admin_verbs() {
        let line = help
            .lines()
            .find(|l| l.trim_start().starts_with(verb.verb))
            .unwrap_or_else(|| panic!("'{}' has no help line", verb.verb));
        assert!(
            line.contains("[admin]"),
            "'{}' needs Administrator but its help line does not say so: {line}",
            verb.verb
        );
    }
    probe("help_bytes", help.len());
    probe("help_lines", help.lines().count());

    // The two tabs with no registry verbs are hand-built surfaces, and they must
    // not appear as empty headings.
    assert!(
        !help.contains("\n  Customization:"),
        "Customization carries no verbs and must be skipped"
    );
    assert!(
        !help.contains("\n  About:"),
        "About carries no verbs and must be skipped"
    );
}

#[test]
fn adding_a_verb_is_one_registry_entry_and_nothing_else() {
    // The extension rule, proven rather than asserted. A synthetic verb is pushed
    // through the SAME rendering path the real help uses; it must appear under
    // its own heading with its own text. This is what "one row and nothing else"
    // means, and it is why `render_help` takes the table as a parameter.
    let extra = Verb {
        verb: "zz-extension-probe",
        script: "demo-stream.ps1",
        arguments: "-Lines [n]",
        requires_admin: false,
        help: "A synthetic verb used to prove the extension rule",
        tab: "Debugging",
        label: "Extension Probe",
        is_read_only: true,
        fixed_arguments: &[],
        render_in_gui: true,
        hint: "",
        action_label: "Probe",
        numeric_only: false,
    };
    let mut table: Vec<Verb> = registry::registry().to_vec();
    table.push(extra);

    let help = registry::render_help(&table, &TABS);
    assert!(help.contains("zz-extension-probe"));
    assert!(help.contains("A synthetic verb used to prove the extension rule"));

    // And the derived flags follow from the shape with no extra wiring.
    let added = registry::find_in(&table, "zz-extension-probe").unwrap();
    assert!(
        added.accepts_user_arguments(),
        "`[n]` means it takes a value"
    );
    assert!(
        !added.requires_a_value(),
        "`[n]` is optional, so a bare dispatch is legitimate"
    );
    assert_eq!(added.button_label(), "Probe");
    probe("extension_rule", "renders-with-one-entry");
}

#[test]
fn the_documented_counts_are_the_counts_the_table_actually_has() {
    // The documents said 28. The table carries the truth, and this test states it
    // in the evidence so the prose can be corrected against a measurement rather
    // than against another sentence.
    let verbs = registry::registry();
    probe("registry_total", verbs.len());
    probe("tabs_total", TABS.len());
    assert_eq!(TABS.len(), 8, "the eight tabs of the shell");
    assert_eq!(
        verbs.len(),
        35,
        "the shipped registry size — update ADR-0018 if a row is genuinely added"
    );
}

#[test]
fn the_timeout_option_is_the_callers_and_never_reaches_a_script() {
    // `-TimeoutSeconds` bounds the INVOCATION, so it is consumed by the caller
    // rather than forwarded: every script in the repo would fail parameter
    // binding on an option it never declared. The WPF build strips it in the same
    // place for the same reason, so this is parity, not a new rule.
    use dashboard_core::strip_timeout_option;

    let args = |list: &[&str]| list.iter().map(|s| s.to_string()).collect::<Vec<_>>();

    assert_eq!(
        strip_timeout_option(&args(&["-Lines", "40", "-TimeoutSeconds", "5"])),
        args(&["-Lines", "40"]),
        "the pair is consumed and the script arguments survive in order"
    );
    assert_eq!(
        strip_timeout_option(&args(&["-TimeoutSeconds", "5"])),
        Vec::<String>::new(),
        "the option alone leaves nothing to forward"
    );
    assert_eq!(
        strip_timeout_option(&args(&["-TimeoutSeconds"])),
        Vec::<String>::new(),
        "a malformed pair must not leave a stray token behind"
    );
    assert_eq!(
        strip_timeout_option(&args(&["-lines", "40"])),
        args(&["-lines", "40"]),
        "unrelated arguments are untouched"
    );
    assert_eq!(
        strip_timeout_option(&args(&["-TimeoutSeconds", "5", "-Lines", "40"])),
        args(&["-Lines", "40"]),
        "only the first pair is consumed, matching what the budget reader sees"
    );
    assert_eq!(
        strip_timeout_option(&args(&["-TimeoutSeconds", "5", "-TimeoutSeconds", "9"])),
        args(&["-TimeoutSeconds", "9"]),
        "a second pair is left alone rather than silently swallowed"
    );

    // The option is case-insensitive, exactly as the PowerShell scripts are: a
    // user typing `-timeoutseconds` must not get a binding failure from the script.
    assert_eq!(
        strip_timeout_option(&args(&["-LINES", "4", "-timeoutseconds", "8"])),
        args(&["-LINES", "4"]),
        "the option is matched case-insensitively"
    );
}

#[test]
fn the_two_part_ahk_spelling_folds_onto_its_own_row() {
    // ADR-0013 spells `ahk enable <name>` / `ahk disable <name>` while the
    // registry keeps the per-script forms as their own rows. The fold is what
    // makes the two spellings agree, and its consequence is checkable from the
    // table alone: the folded row declares a REQUIRED key, while bare `ahk`
    // declares none. So sending `ahk enable` with no key must be refused for the
    // missing key — which can only happen if the fold resolved.
    let bare = registry::find("ahk").expect("ahk is registered");
    let enable = registry::find("ahk-enable").expect("ahk-enable is registered");

    assert!(
        !bare.requires_a_value(),
        "bare `ahk` takes no value, so a refusal of `ahk enable` cannot come from it"
    );
    assert!(
        enable.requires_a_value(),
        "ahk-enable requires its key, which is what makes the bare fold refusable"
    );
    assert!(enable.accepts_user_arguments());
    assert_ne!(
        bare.script, enable.script,
        "the fold must change which script runs"
    );
}

#[test]
fn a_caller_budget_is_read_before_the_option_is_stripped() {
    // The regression this pins: the budget has to be resolved from the ORIGINAL
    // arguments, because the strip that runs immediately after would remove the
    // only occurrence of `-TimeoutSeconds`. Reading it afterwards silently falls
    // back to the 300 s default, so a caller's own timeout is ignored with no
    // error anywhere — the run just takes five minutes instead of five seconds.
    use dashboard_core::{strip_timeout_option, timeout_for, DEFAULT_TIMEOUT};
    use std::time::Duration;

    let args = |list: &[&str]| list.iter().map(|s| s.to_string()).collect::<Vec<_>>();
    let original = args(&["-Lines", "80", "-TimeoutSeconds", "5"]);

    assert_eq!(
        timeout_for(&original),
        Duration::from_secs(5),
        "the budget is read from the original arguments"
    );
    assert_eq!(
        timeout_for(&strip_timeout_option(&original)),
        DEFAULT_TIMEOUT,
        "and reading it after the strip finds nothing — which is why the order matters"
    );
}
