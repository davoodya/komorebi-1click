// Ticket 11 — the About tab's pure surface.
import { describe, expect, it } from 'vitest';
import { AUTHOR, LINKS, PRODUCT_NAME, SUMMARY, copyText, versionLine } from '../lib/about';
import type { AppInfo } from '../lib/ipc';

const info = (): AppInfo => ({
  product: PRODUCT_NAME,
  version: '1.2.3',
  gitSha: 'abc1234',
  scriptsPath: 'C:\\repo\\scripts',
  settingsPath: 'C:\\Users\\me\\AppData\\Roaming\\KomorebiDashboard',
  elevated: true,
  exePath: 'C:\\repo\\KomorebiDashboard.exe',
  runtimeDescription: 'Tauri 2 · windows'
});

describe('the About tab', () => {
  it('names the product and the author, in English', () => {
    expect(PRODUCT_NAME).toBe('Komorebi Admin Dashboard');
    expect(AUTHOR).toContain('Davood');
    expect(SUMMARY).toMatch(/same registry/);
  });

  it('shows the version and the Git SHA the build was stamped with', () => {
    expect(versionLine(info())).toBe('v1.2.3 · abc1234');
    // A development build says so rather than printing "unknown".
    expect(versionLine(null)).toBe('v0.1.0 · development');
  });

  it('copies product, version and the executable', () => {
    expect(copyText(info())).toBe(
      'Komorebi Admin Dashboard v1.2.3 · abc1234\nC:\\repo\\KomorebiDashboard.exe'
    );
  });

  it('offers the site and repository links, and only those two', () => {
    // A closed set: the backend resolves the URLs, the frontend never builds
    // an arbitrary one.
    expect(LINKS.map((l) => l.kind)).toEqual(['site', 'repository']);
  });
});
