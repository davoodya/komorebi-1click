use dashboard_core::registry::{self, registry};

#[tokio::test]
async fn dispatch_streams_both_pipes_and_preserves_script_exit_code() {
    let scripts = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../scripts");
    let mut batches = Vec::new();
    let result = dashboard_core::run(
        &scripts,
        "demo-stream",
        &[
            "-Lines".into(),
            "80".into(),
            "-DelayMs".into(),
            "2".into(),
            "-FailWith".into(),
            "7".into(),
        ],
        "test-run",
        |batch| {
            batches.push(batch);
        },
    )
    .await;
    assert_eq!(result.exit_code, 7);
    assert!(result.stdout.contains("line 80/80"));
    assert!(result.stderr.contains("stderr checkpoint at line 80"));
    assert!(batches.len() > 1, "output must stream before completion");
    assert!(
        batches.len() < 40,
        "output must be batched, not emitted per line"
    );
    assert!(batches.iter().all(|b| b.run_id == "test-run"));
}

/// The three ways a request is refused, and the ordering that matters: each one
/// must be decided BEFORE a process is created, so the run that is refused is
/// provably untouched.
///
/// `restart-all` is used as the unknown verb on purpose — it is a REAL verb in
/// the shipping registry. Using a typo would prove the parser rejects nonsense;
/// using a real verb name in the absent-scripts directory proves the lookup
/// happens against the table and then fails at the filesystem, which is the
/// ordering the 127 contract describes.
#[tokio::test]
async fn invalid_requests_fail_before_any_script_can_run() {
    let absent = std::env::temp_dir().join("komorebi-dashboard-no-such-scripts");
    let mut batches = 0;

    // An unknown verb: no row, exit 2, usage on stderr.
    let unknown =
        dashboard_core::run(&absent, "no-such-verb", &[], "unknown", |_| batches += 1).await;
    assert_eq!(unknown.exit_code, 2);
    assert!(unknown.stderr.contains("Unknown verb"));
    assert!(unknown.stderr.contains("Usage:"));

    // A real verb, but this directory has no scripts: 127 naming the file the
    // registry asked for, which is what tells the user where it looked.
    let missing =
        dashboard_core::run(&absent, "restart-all", &[], "missing", |_| batches += 1).await;
    assert_eq!(missing.exit_code, 127);
    assert!(missing.stderr.contains("restart-all.ps1"));

    // A verb that declares no value must not accept one. `status` is the case
    // that matters: letting `-Action install` through would turn the
    // unprivileged health check into an administrative operation.
    let override_action = dashboard_core::run(
        &absent,
        "status",
        &["-Action".into(), "install".into()],
        "override",
        |_| batches += 1,
    )
    .await;
    assert_eq!(override_action.exit_code, 2);
    assert!(override_action.stderr.contains("accepts no arguments"));

    // A bare dispatch of a verb whose shape REQUIRES a value is a request for
    // help, not a run: launching it would hand the script a missing argument and
    // report a bind failure as if the operation had failed.
    let bare = dashboard_core::run(&absent, "uninstall", &[], "bare", |_| batches += 1).await;
    assert_eq!(bare.exit_code, 2);
    assert!(bare.stderr.contains("needs a value"));

    // Nothing was ever launched: an empty scripts directory cannot produce a
    // process, and the batch counter proves no output arrived either.
    assert_eq!(batches, 0);
}

#[test]
fn published_layout_resolves_repo_scripts_and_help_lists_the_whole_registry() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .unwrap();
    let resolved =
        dashboard_core::locate_scripts(&root.join("releases/rust/KomorebiDashboard.exe"));
    assert_eq!(resolved, root.join("scripts"));

    // Ticket 01 asserted help exposed ONLY the two tracer verbs. That was the
    // tracer's contract and ticket 03 replaces it: help now covers the whole
    // table, generated from the rows.
    let help = dashboard_core::help();
    for verb in registry() {
        assert!(
            help.contains(verb.verb),
            "{} missing from --help",
            verb.verb
        );
    }
    assert!(help.contains("Kill and Start:"));
    assert!(help.contains("[admin]"));
}

#[test]
fn the_registry_invariants_live_in_the_registry_suite() {
    // This replaces the tracer's "exactly two verbs" assertion, which ticket 03
    // retired by design. The per-row invariants (unique names, one tab each,
    // every script present, the count) are asserted where they belong — over the
    // whole table in `tests/registry.rs` — and this records the move so the
    // deletion is deliberate rather than a lost assertion.
    assert!(
        registry().len() > 2,
        "the tracer's two-verb stub must have been replaced by the full registry"
    );
    assert!(registry::find("status").is_some());
    assert!(registry::find("demo-stream").is_some());
}
