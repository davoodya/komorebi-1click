use dashboard_core::registry;

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

use std::collections::HashSet;

#[tokio::test]
async fn invalid_requests_fail_before_any_script_can_run() {
    let absent = std::env::temp_dir().join("komorebi-dashboard-no-such-scripts");
    let mut batches = 0;
    let unknown =
        dashboard_core::run(&absent, "restart-all", &[], "unknown", |_| batches += 1).await;
    assert_eq!(unknown.exit_code, 2);
    assert!(unknown.summary.contains("Usage:"));
    let override_action = dashboard_core::run(
        &absent,
        "status",
        &["-Action".into(), "install".into()],
        "override",
        |_| batches += 1,
    )
    .await;
    assert_eq!(override_action.exit_code, 2);
    let missing = dashboard_core::run(&absent, "status", &[], "missing", |_| batches += 1).await;
    assert_eq!(missing.exit_code, 127);
    assert!(missing.stderr.contains("komorebi-service.ps1"));
    assert_eq!(batches, 0);
}

#[test]
fn published_layout_resolves_repo_scripts_and_help_exposes_only_the_tracer() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .unwrap();
    let resolved =
        dashboard_core::locate_scripts(&root.join("releases/rust/KomorebiDashboard.exe"));
    assert_eq!(resolved, root.join("scripts"));
    let help = dashboard_core::help();
    assert!(help.contains("status"));
    assert!(help.contains("demo-stream"));
    assert!(!help.contains("restart-all"));
    assert!(registry().iter().all(|v| v.is_read_only));
    assert_eq!(registry()[0].fixed_arguments, ["-Action", "status"]);
}

#[test]
fn tracer_bullet_declares_two_unique_real_readonly_scripts() {
    let verbs = registry();
    assert_eq!(
        verbs.iter().map(|v| v.verb).collect::<Vec<_>>(),
        ["status", "demo-stream"]
    );
    assert_eq!(
        verbs.iter().map(|v| v.verb).collect::<HashSet<_>>().len(),
        2
    );
    let scripts = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../scripts");
    for verb in verbs {
        assert!(scripts.join(verb.script).is_file(), "{}", verb.script);
    }
}
