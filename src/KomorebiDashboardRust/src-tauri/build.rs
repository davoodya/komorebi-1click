// The About tab must show the project's logo and the Git SHA this build was
// stamped with (roadmap DoD), so both are baked in at COMPILE time: rewriting
// the executable to inject a SHA after the fact would desync hash and bytes,
// and resolving the logo from a runtime path only works after someone copies
// a file beside the executable (a `--no-bundle` build lays no resources out).
//
// `tauri_build::build()` FIRST and unchanged: it generates the Tauri context
// the `generate_context!` macro embeds (and on Windows the icon resource).
// Dropping it compiles but ships a binary that cannot start.
//
// The logo ships as `logo.ico` — a multi-size container. Embedding the whole
// 353 KB container to display a 48x48 mark would bloat the binary for no
// gain, so this script extracts the 48x48 entry (a PNG inside the container)
// into OUT_DIR as `about-logo.png`, and `main.rs` embeds THAT.
//
// The SHA stamp is only as good as the tree it came from:
// - A committed tree stamps the commit's full SHA.
// - A dirty tree appends +dirty so a locally-built binary is never mistaken
//   for the published one.
// - No git repo at all (or no git binary) stamps "development".
//
// `rerun-if-changed` points at the git refs and HEAD so a new commit
// re-stamps without touching sources.

use std::fs;
use std::path::PathBuf;
use std::process::Command;

const LOGO_ICO: &str = "../../KomorebiDashboard/Resources/logo.ico";
const ABOUT_LOGO_SIZE: u16 = 48;

fn main() {
    #[cfg(feature = "desktop")]
    tauri_build::build();

    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed={LOGO_ICO}");
    for dir in ["../.git/HEAD", "../.git/refs"] {
        println!("cargo:rerun-if-changed={dir}");
    }

    let sha = git_sha().unwrap_or_else(|| "development".to_string());
    println!("cargo:rustc-env=DASHBOARD_GIT_SHA={sha}");

    if let Err(error) = write_about_logo() {
        // A missing logo must never fail the build: the About tab falls back
        // to the typographic mark. The build says why on stderr.
        println!("cargo:warning=about logo unavailable: {error}");
    }
}

/// Extract the first `48x48` image from the .ico container into
/// `OUT_DIR/about-logo.png`.
///
/// An .ico directory entry is 16 bytes: width, height (0 means 256), colour
/// count, reserved, planes, bit count, byte length, byte offset. The image
/// payload follows the directory and for modern icons IS a PNG.
fn write_about_logo() -> Result<(), String> {
    let data = fs::read(LOGO_ICO).map_err(|e| format!("read {LOGO_ICO}: {e}"))?;
    if data.len() < 6 {
        return Err("ico too small".to_string());
    }
    let count = u16::from_le_bytes([data[4], data[5]]) as usize;
    let mut offset = 6usize;
    for _ in 0..count {
        if offset + 16 > data.len() {
            return Err("ico directory ends early".to_string());
        }
        let width = data[offset] as u16;
        let height = data[offset + 1] as u16;
        let size = u32::from_le_bytes([
            data[offset + 8],
            data[offset + 9],
            data[offset + 10],
            data[offset + 11],
        ]) as usize;
        let start = u32::from_le_bytes([
            data[offset + 12],
            data[offset + 13],
            data[offset + 14],
            data[offset + 15],
        ]) as usize;
        offset += 16;
        let w = if width == 0 { 256 } else { width };
        let h = if height == 0 { 256 } else { height };
        if w == ABOUT_LOGO_SIZE && h == ABOUT_LOGO_SIZE {
            let end = start.saturating_add(size);
            let png = data
                .get(start..end)
                .ok_or_else(|| "ico entry runs past the file".to_string())?;
            let mut path = PathBuf::from(
                std::env::var("OUT_DIR").map_err(|e| format!("OUT_DIR missing: {e}"))?,
            );
            path.push("about-logo.png");
            fs::write(&path, png).map_err(|e| format!("write {}: {e}", path.display()))?;
            return Ok(());
        }
    }
    Err(format!("no {ABOUT_LOGO_SIZE}x{ABOUT_LOGO_SIZE} entry in the container"))
}

fn git_sha() -> Option<String> {
    let output = Command::new("git")
        .args(["rev-parse", "HEAD"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let sha = String::from_utf8(output.stdout).ok()?.trim().to_string();
    if sha.is_empty() || !sha.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    // A dirty tree stamps differently — a locally built binary says so.
    let status = Command::new("git")
        .args(["status", "--porcelain"])
        .output()
        .ok();
    let dirty = match status {
        Some(o) => o.status.success() && !o.stdout.is_empty(),
        None => false,
    };
    Some(if dirty {
        format!("{sha}+dirty")
    } else {
        sha
    })
}
