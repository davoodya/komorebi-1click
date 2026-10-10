// Ticket 12 — the elevation gate, the core's half.
//
// The WPF build enforced this per verb in its own dispatch; the Rust twin
// enforces it in the ONE place both the window and the CLI run through, so
// a second implementation cannot drift from the first. The gate is pure over
// (verb, elevated): the platform probe lives beside it and is deliberately
// thin, because "am I elevated?" is an OS question and everything else is
// logic that can be tested on any machine.
use dashboard_core::registry::{self, Verb};
use dashboard_core::*;

fn verb(name: &str, requires_admin: bool) -> Verb {
    registry::find(name)
        .map(|v| Verb {
            requires_admin,
            ..*v
        })
        .expect("known verb")
}

#[test]
fn an_administrative_verb_unelevated_asks_for_a_relaunch() {
    match elevation_gate(&verb("kill-all", true), false) {
        ElevationGate::NeedsRelaunch { .. } => {}
        ElevationGate::Allowed => panic!("an admin verb unelevated must not run"),
    }
}

#[test]
fn an_administrative_verb_elevated_is_allowed() {
    assert!(matches!(
        elevation_gate(&verb("kill-all", true), true),
        ElevationGate::Allowed
    ));
}

#[test]
fn a_non_administrative_verb_is_never_gated() {
    assert!(matches!(
        elevation_gate(&verb("status", false), false),
        ElevationGate::Allowed
    ));
}

#[test]
fn the_gate_names_the_specific_features_from_the_registry() {
    // The message must name real rows with RequiresAdmin set in THE table
    // a generic "needs admin" line is what the ticket forbids.
    let gated = registry::registry().iter().filter(|v| v.requires_admin).count();
    assert!(gated > 0, "the registry has administrative verbs to name");
    if let ElevationGate::NeedsRelaunch { features } =
        elevation_gate(&verb("kill-all", true), false)
    {
        assert_eq!(features.len(), gated, "every admin row is named");
        assert!(
            features.iter().all(|f| !f.is_empty()),
            "a named feature is never blank"
        );
    } else {
        panic!("expected a relaunch request");
    }
}

#[test]
fn the_refusal_is_a_structured_result_with_its_own_exit_code() {
    let result = needs_elevation_result(&verb("kill-all", true), "t12-gate");
    assert_eq!(result.exit_code, EXIT_NEEDS_ELEVATION);
    assert_eq!(result.verb, "kill-all");
    assert!(!result.cancelled && !result.timed_out, "a refusal is neither");
    assert!(
        result.summary.contains("Kill All") || result.summary.contains("Administrator"),
        "the refusal explains itself: {}",
        result.summary
    );
}

/// The refusal reaches a caller through the REAL dispatch path, not just the
/// pure gate: the CLI's exit code comes from this result, so this is the test
/// that proves "exits non-zero rather than silently doing nothing".
///
/// It deliberately skips when the test process IS elevated, because an
/// elevated run would actually launch kill-all — the gate would allow it and
/// the box would lose its window manager. The pure logic above is what covers
/// the elevated case.
#[tokio::test]
async fn the_cli_refuses_an_administrative_verb_before_launching_it() {
    if dashboard_core::is_elevated() {
        eprintln!("[probe] elevated-process=true (gate allows admin verbs; launch test skipped)");
        return;
    }
    let scripts = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../scripts");
    let mut batches = 0;
    let result =
        dashboard_core::run(&scripts, "kill-all", &[], "t12-cli", |_| batches += 1).await;
    assert_eq!(result.exit_code, EXIT_NEEDS_ELEVATION);
    assert!(
        result.summary.contains("Administrator") || result.stderr.contains("Administrator"),
        "the refusal names the reason: {}",
        result.summary
    );
    assert_eq!(batches, 0, "nothing launched, so no output arrived");
}
