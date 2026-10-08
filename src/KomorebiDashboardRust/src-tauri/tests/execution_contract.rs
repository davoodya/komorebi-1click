//! Ticket 02 — the execution contract: batching, cancel, timeout, tree kill.
//!
//! These run the real `demo-stream.ps1` fixture through the same `run`/`execute`
//! path the window and the CLI use. That is deliberate: the contract is about
//! what actually happens to a real child process, and a mock would not tell us
//! whether a grandchild survived a kill.

use std::time::{Duration, Instant};

fn scripts() -> std::path::PathBuf {
    std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../scripts")
}

/// A pid no real process holds, used to prove that a run which never launched a
/// process reports the missing-script error instead of a stray kill.
fn absent_scripts() -> std::path::PathBuf {
    std::env::temp_dir().join("komorebi-dashboard-ticket02-no-scripts")
}

/// Machine-readable evidence line.
///
/// `tests/rust-ticket02-probe.ps1` parses these out of `cargo test -- --nocapture`
/// to assemble its artifact. Printing the measured numbers from the test that
/// measured them is the point: a hand-written summary file drifts from what the
/// code actually does, a parsed measurement cannot.
fn probe(field: &str, value: impl std::fmt::Display) {
    println!("[probe] {field}={value}");
}

#[tokio::test]
async fn cancel_stops_the_child_and_reports_a_cancelled_run() {
    // 600 lines at 50 ms is 30 s of work; the cancel must land in well under that.
    let scripts = scripts();
    let run_id = "ticket02-cancel";
    let started = Instant::now();

    let worker = tokio::spawn({
        let scripts = scripts.clone();
        async move {
            dashboard_core::run(
                &scripts,
                "demo-stream",
                &[
                    "-Lines".into(),
                    "600".into(),
                    "-DelayMs".into(),
                    "50".into(),
                ],
                run_id,
                |_| {},
            )
            .await
        }
    });

    // Give the child time to actually start emitting, then cancel it.
    tokio::time::sleep(Duration::from_millis(600)).await;
    assert!(
        dashboard_core::request_cancel(run_id),
        "a live run must be reachable by its run id"
    );

    let result = tokio::time::timeout(Duration::from_secs(20), worker)
        .await
        .expect("a cancelled run must not hang")
        .expect("the run task must not panic");

    let elapsed = started.elapsed();
    assert!(
        elapsed < Duration::from_secs(20),
        "cancelling must stop the run, not wait it out (took {elapsed:?})"
    );
    assert!(result.cancelled, "the run must be recorded as cancelled");
    assert!(
        !result.timed_out,
        "a user cancel is not a timeout — the two facts must not collapse"
    );
    assert_eq!(result.exit_code, dashboard_core::CANCELLED_EXIT_CODE);
    assert!(
        result.summary.contains("CANCELLED"),
        "the verdict must say cancelled, got {}",
        result.summary
    );
    // It was stopped part-way, so it cannot have finished all 600 lines.
    assert!(
        !result.stdout.contains("line 600/600"),
        "a cancelled run must not have completed its work"
    );

    probe("cancel.elapsed_ms", elapsed.as_millis());
    probe("cancel.exit_code", result.exit_code);
    probe("cancel.cancelled", result.cancelled);
    probe("cancel.timed_out", result.timed_out);
    probe("cancel.budget_ms", 30_000);
    probe(
        "cancel.completed_work",
        result.stdout.contains("line 600/600"),
    );
}

#[tokio::test]
async fn cancelling_an_unknown_or_finished_run_is_reported_honestly() {
    assert!(
        !dashboard_core::request_cancel("no-such-run-id"),
        "cancelling a run that is not live must report false, not pretend success"
    );
    // A run that has already finished must no longer be cancellable.
    let scripts = scripts();
    let result = dashboard_core::run(
        &scripts,
        "demo-stream",
        &["-Lines".into(), "1".into(), "-DelayMs".into(), "0".into()],
        "ticket02-finished",
        |_| {},
    )
    .await;
    assert_eq!(result.exit_code, 0);
    assert!(!result.cancelled);
    assert!(
        !dashboard_core::request_cancel("ticket02-finished"),
        "a finished run must be deregistered, so a late cancel cannot look successful"
    );
}

#[tokio::test]
async fn a_run_that_overruns_its_budget_is_timed_out_and_not_failed() {
    // -TimeoutSeconds is the dashboard's own budget; the fixture documents that
    // it does not enforce it itself, the caller does. 200 lines at 100 ms would
    // take 20 s, so a 3 s budget must cut it short.
    let scripts = scripts();
    let started = Instant::now();
    let mut batches = 0;

    let result = dashboard_core::run(
        &scripts,
        "demo-stream",
        &[
            "-Lines".into(),
            "200".into(),
            "-DelayMs".into(),
            "100".into(),
            "-TimeoutSeconds".into(),
            "3".into(),
        ],
        "ticket02-timeout",
        |_| batches += 1,
    )
    .await;

    let elapsed = started.elapsed();
    assert!(result.timed_out, "the run must be recorded as timed out");
    assert!(
        !result.cancelled,
        "a timeout is not a cancellation — the two facts must not collapse"
    );
    assert_eq!(
        result.exit_code,
        dashboard_core::TIMEOUT_EXIT_CODE,
        "a timeout reports 124, not the script's own code"
    );
    assert!(
        result.summary.contains("TIMED OUT"),
        "the verdict must say TIMED OUT, never FAILED; got {}",
        result.summary
    );
    assert!(
        !result.summary.contains("FAILED"),
        "a timeout must not be reported as a failure"
    );
    assert!(
        elapsed >= Duration::from_secs(3) && elapsed < Duration::from_secs(15),
        "the budget must be honoured near 3 s, not ignored (took {elapsed:?})"
    );
    assert!(
        batches > 0,
        "output before the timeout must still be streamed"
    );
    assert!(
        !result.stdout.contains("line 200/200"),
        "the run was cut short, so it cannot have finished"
    );

    probe("timeout.budget_ms", 3_000);
    probe("timeout.elapsed_ms", elapsed.as_millis());
    probe("timeout.exit_code", result.exit_code);
    probe("timeout.timed_out", result.timed_out);
    probe("timeout.cancelled", result.cancelled);
    probe("timeout.verdict", result.summary.clone());
    probe("timeout.reported_failed", result.summary.contains("FAILED"));
    probe("timeout.streamed_before_stop", batches > 0);
}

#[tokio::test]
async fn no_process_survives_a_stop_and_the_tree_kill_takes_the_children_too() {
    // The child PowerShell is the direct target; its `Start-Sleep` is the
    // grandchild. Killing only the direct child leaves the grandchild holding the
    // pipe handles, which is exactly the hang the WPF build documented.
    let scripts = scripts();
    let run_id = "ticket02-tree";
    let mut pids: Vec<u32> = Vec::new();

    let worker = tokio::spawn({
        let scripts = scripts.clone();
        async move {
            dashboard_core::run(
                &scripts,
                "demo-stream",
                &[
                    "-Lines".into(),
                    "600".into(),
                    "-DelayMs".into(),
                    "50".into(),
                ],
                run_id,
                |_| {},
            )
            .await
        }
    });

    tokio::time::sleep(Duration::from_millis(700)).await;
    // Capture what is alive before the cancel, so afterwards we can assert the
    // same pids are gone rather than just "something died".
    for line in running_demo_stream_processes() {
        pids.push(line);
    }
    assert!(
        !pids.is_empty(),
        "the fixture must be running before the tree kill is tested"
    );

    assert!(dashboard_core::request_cancel(run_id));
    let result = tokio::time::timeout(Duration::from_secs(20), worker)
        .await
        .expect("the run must not hang after a tree kill")
        .expect("task must not panic");
    assert!(result.cancelled);

    // Bounded settle: taskkill is asynchronous, so give it a moment to reap.
    let mut survivors = pids.clone();
    for _ in 0..20 {
        survivors.retain(|pid| dashboard_core::process_exists(*pid));
        if survivors.is_empty() {
            break;
        }
        tokio::time::sleep(Duration::from_millis(250)).await;
    }
    assert!(
        survivors.is_empty(),
        "no process from the run may survive the tree kill; still alive: {survivors:?}"
    );

    probe("tree.pids_before_kill", pids.len());
    probe("tree.survivors", survivors.len());
}

/// Pids of the PowerShell processes running our fixture, read from the command
/// line so an unrelated PowerShell is never touched or asserted about.
fn running_demo_stream_processes() -> Vec<u32> {
    let output = std::process::Command::new("powershell.exe")
        .args([
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe' or Name='pwsh.exe'\" \
             | Where-Object { $_.CommandLine -like '*demo-stream.ps1*' } \
             | Select-Object -ExpandProperty ProcessId",
        ])
        .output();
    match output {
        Ok(output) => String::from_utf8_lossy(&output.stdout)
            .split_whitespace()
            .filter_map(|value| value.trim().parse::<u32>().ok())
            .collect(),
        Err(_) => Vec::new(),
    }
}

#[test]
fn the_timeout_budget_comes_from_the_arguments_with_a_300s_default() {
    // The default is the documented contract, so it is asserted rather than
    // assumed, and an explicit budget must win.
    assert_eq!(dashboard_core::timeout_for(&[]), Duration::from_secs(300));
    assert_eq!(
        dashboard_core::timeout_for(&["-Lines".into(), "50".into()]),
        Duration::from_secs(300)
    );
    assert_eq!(
        dashboard_core::timeout_for(&["-TimeoutSeconds".into(), "3".into()]),
        Duration::from_secs(3)
    );
    // Case matters to PowerShell but not to a user typing it.
    assert_eq!(
        dashboard_core::timeout_for(&["-timeoutseconds".into(), "7".into()]),
        Duration::from_secs(7)
    );
    // A malformed or zero budget must fall back rather than produce an instant
    // timeout, which would look like a spontaneous failure.
    assert_eq!(
        dashboard_core::timeout_for(&["-TimeoutSeconds".into(), "nonsense".into()]),
        Duration::from_secs(300)
    );
    assert_eq!(
        dashboard_core::timeout_for(&["-TimeoutSeconds".into(), "0".into()]),
        Duration::from_secs(300)
    );
    assert_eq!(
        dashboard_core::timeout_for(&["-TimeoutSeconds".into()]),
        Duration::from_secs(300)
    );
}

#[tokio::test]
async fn a_missing_script_reports_127_and_never_launches_power_shell() {
    let absent = absent_scripts();
    let mut batches = 0;
    let result =
        dashboard_core::run(&absent, "status", &[], "ticket02-missing", |_| batches += 1).await;
    assert_eq!(result.exit_code, 127);
    assert!(
        result.stderr.contains("komorebi-service.ps1"),
        "the offending path must be named, got {}",
        result.stderr
    );
    assert!(!result.cancelled && !result.timed_out);
    assert_eq!(
        batches, 0,
        "nothing may be streamed for a script that never ran"
    );
    // A run that never launched must not be registered as live either.
    assert!(!dashboard_core::request_cancel("ticket02-missing"));

    probe("missing_script.exit_code", result.exit_code);
    probe("missing_script.batches", batches);
    probe(
        "missing_script.names_path",
        result.stderr.contains("komorebi-service.ps1"),
    );
}

#[tokio::test]
async fn a_non_zero_exit_surfaces_the_code_duration_and_the_full_output() {
    let scripts = scripts();
    let result = dashboard_core::run(
        &scripts,
        "demo-stream",
        &[
            "-Lines".into(),
            "12".into(),
            "-DelayMs".into(),
            "0".into(),
            "-FailWith".into(),
            "9".into(),
        ],
        "ticket02-failure",
        |_| {},
    )
    .await;
    assert_eq!(result.exit_code, 9, "the script's own code must survive");
    assert!(!result.cancelled && !result.timed_out);
    assert!(result.summary.contains("FAILED"), "got {}", result.summary);
    assert!(result.duration_ms > 0, "a duration must be recorded");
    // The full raw output, both streams, is part of the contract — the console
    // pane shows it, so it must not be summarised away.
    assert!(
        result.stdout.contains("line 12/12"),
        "stdout must be complete"
    );
    assert!(
        result.stderr.contains("failing on purpose with code 9"),
        "stderr must be complete"
    );

    probe("failure.exit_code", result.exit_code);
    probe("failure.duration_ms", result.duration_ms);
    probe("failure.stdout_bytes", result.stdout.len());
    probe("failure.stderr_bytes", result.stderr.len());
}

#[tokio::test]
async fn a_high_line_count_run_stays_batched_and_does_not_block_the_caller() {
    // 1000 lines with no delay is the "no freeze, no per-line emit" case.
    //
    // The gap measured below is between successive emits, and the first emit is
    // deliberately excluded: it arrives only after PowerShell has spawned, which
    // is process startup time, not a streaming stall. Measuring from the first
    // emit onward is what actually tests "output keeps moving in bounded
    // windows", which is what keeps the window responsive.
    let scripts = scripts();
    let mut batches = 0;
    let mut worst_gap = Duration::ZERO;
    let mut last: Option<Instant> = None;
    let started = Instant::now();

    let result = dashboard_core::run(
        &scripts,
        "demo-stream",
        &[
            "-Lines".into(),
            "1000".into(),
            "-DelayMs".into(),
            "0".into(),
        ],
        "ticket02-chatty",
        |_| {
            if let Some(previous) = last {
                worst_gap = worst_gap.max(previous.elapsed());
            }
            last = Some(Instant::now());
            batches += 1;
        },
    )
    .await;

    assert_eq!(result.exit_code, 0);
    assert!(result.stdout.contains("line 1000/1000"));
    assert!(
        batches > 1,
        "output must stream as it arrives, not arrive all at the end"
    );
    // 1000 lines must NOT arrive as 1000 emits: that is the per-line emit the
    // contract forbids. Batching at 50 ms bounds this near 20 for a fast run.
    assert!(
        batches < 60,
        "1000 lines must be batched, not emitted per line (got {batches} batches)"
    );
    // Every window after the first arrives within a few batch intervals, so the
    // reader is never left waiting on output that has already been produced.
    assert!(
        worst_gap < Duration::from_millis(250),
        "output windows must keep arriving while the run streams (worst gap {worst_gap:?})"
    );
    assert!(
        started.elapsed() < Duration::from_secs(90),
        "a chatty run must complete promptly"
    );

    probe("batching.lines", 1000);
    probe("batching.batches", batches);
    probe("batching.worst_gap_ms", worst_gap.as_millis());
    probe("batching.elapsed_ms", started.elapsed().as_millis());
    probe("batching.per_line_emit", batches >= 1000);
}

#[tokio::test]
async fn concurrent_runs_are_independently_cancellable_by_run_id() {
    // Two runs alive at once, each reachable and stoppable on its own id. This is
    // what the per-run registry buys over a single global busy flag.
    let scripts = scripts();
    let first = tokio::spawn({
        let scripts = scripts.clone();
        async move {
            dashboard_core::run(
                &scripts,
                "demo-stream",
                &[
                    "-Lines".into(),
                    "600".into(),
                    "-DelayMs".into(),
                    "50".into(),
                ],
                "ticket02-a",
                |_| {},
            )
            .await
        }
    });
    let second = tokio::spawn({
        let scripts = scripts.clone();
        async move {
            dashboard_core::run(
                &scripts,
                "demo-stream",
                &[
                    "-Lines".into(),
                    "600".into(),
                    "-DelayMs".into(),
                    "50".into(),
                ],
                "ticket02-b",
                |_| {},
            )
            .await
        }
    });

    tokio::time::sleep(Duration::from_millis(600)).await;
    assert!(dashboard_core::request_cancel("ticket02-a"));
    let a = tokio::time::timeout(Duration::from_secs(20), first)
        .await
        .expect("cancelled run must settle")
        .unwrap();
    assert!(a.cancelled);

    // Cancelling one run must not have disturbed the other, which keeps running
    // until it is told to stop. That is the guarantee a shared flag cannot give.
    assert!(
        dashboard_core::request_cancel("ticket02-b"),
        "the second run must still be live after the first was cancelled"
    );
    let b = tokio::time::timeout(Duration::from_secs(20), second)
        .await
        .expect("second cancelled run must settle")
        .unwrap();
    assert!(b.cancelled);
    assert!(!b.timed_out);
}
