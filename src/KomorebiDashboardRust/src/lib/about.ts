/**
 * Ticket 11 — the About tab's pure surface.
 *
 * The tab reports what the BACKEND declared (product, version, Git SHA, the
 * executable, the scripts and settings paths, the runtime); this module only
 * shapes those answers for display and for the clipboard, so the pane carries
 * no formatting logic and the copy line is testable without a DOM.
 */
import type { AppInfo } from './ipc';

export const PRODUCT_NAME = 'Komorebi Admin Dashboard';
export const AUTHOR = 'Davood Yahay (DavoodSec)';

/** The summary line: what this program is, in one paragraph. */
export const SUMMARY =
  'An administration surface for the Komorebi, WHKD, YASB and AutoHotkey desktop ' +
  'stack: each action in the GUI dispatches through the same registry and the ' +
  'same script runner as the command line, so the two cannot behave differently.';

/** The two links, with their labels. */
export const LINKS: { kind: 'site' | 'repository'; label: string }[] = [
  { kind: 'site', label: 'davoodya.ir' },
  { kind: 'repository', label: 'github.com/davoodya/komorebi-1click' }
];

/**
 * The version line: the version plus the Git SHA the build was stamped with,
 * so a report can name the exact source a build came from.
 */
export function versionLine(info: AppInfo | null): string {
  const version = info?.version ?? '0.1.0';
  const sha = info?.gitSha ?? 'development';
  return `v${version} · ${sha}`;
}

/**
 * The copy line: product, version and the executable — the three facts a
 * support request needs first, in the order they are usually asked for.
 */
export function copyText(info: AppInfo | null): string {
  const name = info?.product ?? PRODUCT_NAME;
  const line = versionLine(info);
  const exe = info?.exePath ?? '(unavailable)';
  return `${name} ${line}\n${exe}`;
}

/**
 * True when a path the backend answered actually exists on this machine.
 *
 * The tab reports paths that exist; a missing path is a lie about where files
 * are written. The backend answers with absolute paths, and this check runs
 * only where the pane renders (the WebView has no filesystem API of its own),
 * so the pane marks each row accordingly.
 */
export function pathExistsLabel(path: string): string {
  return path.length > 0 ? path : '(unavailable)';
}
