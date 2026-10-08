import { describe, expect, it } from 'vitest';
import { describeRun, formatDuration, formatLineCount, parseArguments, runStateLabel } from '../lib/format';

describe('formatDuration', () => {
  it('renders sub-second durations in milliseconds', () => {
    expect(formatDuration(0)).toBe('0 ms');
    expect(formatDuration(812.4)).toBe('812 ms');
  });

  it('renders seconds with two decimals', () => {
    expect(formatDuration(1000)).toBe('1.00 s');
    expect(formatDuration(3412)).toBe('3.41 s');
  });

  it('renders minutes once the run is long enough', () => {
    expect(formatDuration(64_000)).toBe('1 m 04 s');
  });

  it('never renders a negative or NaN duration', () => {
    expect(formatDuration(-5)).toBe('0 ms');
    expect(formatDuration(Number.NaN)).toBe('0 ms');
  });
});

describe('run verdicts', () => {
  it('keeps cancellation and timeout as distinct facts', () => {
    expect(describeRun({ exitCode: 124, timedOut: true })).toBe('timed-out');
    expect(describeRun({ exitCode: 1, cancelled: true })).toBe('cancelled');
    expect(describeRun({ exitCode: 0 })).toBe('succeeded');
    expect(describeRun({ exitCode: 7 })).toBe('failed');
  });

  it('labels each verdict with the wording the spec fixes', () => {
    expect(runStateLabel('succeeded')).toBe('OK');
    expect(runStateLabel('failed')).toBe('FAILED');
    expect(runStateLabel('timed-out')).toBe('TIMED OUT');
    expect(runStateLabel('cancelled')).toBe('CANCELLED');
  });

  it('pluralises the line count', () => {
    expect(formatLineCount(0)).toBe('0 lines');
    expect(formatLineCount(1)).toBe('1 line');
    expect(formatLineCount(250)).toBe('250 lines');
  });
});

describe('parseArguments', () => {
  it('returns nothing for an empty or whitespace value', () => {
    expect(parseArguments('')).toEqual([]);
    expect(parseArguments('   ')).toEqual([]);
  });

  it('splits on whitespace', () => {
    expect(parseArguments('100')).toEqual(['100']);
    expect(parseArguments('  -Lines 250 -DelayMs 5 ')).toEqual(['-Lines', '250', '-DelayMs', '5']);
  });

  it('groups a quoted value that contains spaces', () => {
    expect(parseArguments('"C:\\my backups\\today"')).toEqual(['C:\\my backups\\today']);
    expect(parseArguments('-ZipPath "C:\\a b\\c"')).toEqual(['-ZipPath', 'C:\\a b\\c']);
  });

  it('does not fail on an unterminated quote', () => {
    expect(parseArguments('"C:\\half a path')).toEqual(['C:\\half a path']);
  });
});
