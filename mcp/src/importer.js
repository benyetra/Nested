import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { HEADER, isValidTimeZone, systemTimeZone, toCsv } from './format.js';
import { parseHuckleberry, tableFromFile } from './huckleberry.js';
import { EventSchema, eventsToRows } from './events.js';

const KIND_LABEL = {
  nursing: 'nursing', bottle: 'bottle', diaper: 'diaper', sleep: 'sleep', pump: 'pump', note: 'note',
};

export function resolveTimeZone(requested) {
  if (!requested) return systemTimeZone();
  if (!isValidTimeZone(requested)) {
    throw new Error(`Unknown timezone '${requested}'. Use an IANA name such as America/New_York.`);
  }
  return requested;
}

/** Where import files go: an iCloud Drive folder if there is one (so they appear in Files on the phone). */
export function defaultOutputDir(env = process.env) {
  if (env.NESTED_IMPORT_DIR) return env.NESTED_IMPORT_DIR;
  const drive = join(homedir(), 'Library', 'Mobile Documents', 'com~apple~CloudDocs');
  if (existsSync(drive)) return join(drive, 'Nested Imports');
  const downloads = join(homedir(), 'Downloads');
  return existsSync(downloads) ? join(downloads, 'Nested Imports') : join(tmpdir(), 'Nested Imports');
}

function describeRow(row, timeZone) {
  const when = new Date(row.started_at).toLocaleString('en-US', {
    timeZone, month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  });
  const bits = [];
  if (row.type === 'nursing') {
    if (row.left_seconds) bits.push(`L ${Math.round(row.left_seconds / 60)}m`);
    if (row.right_seconds) bits.push(`R ${Math.round(row.right_seconds / 60)}m`);
  }
  if (row.type === 'bottle') bits.push(`${Math.round(row.amount_ml)} ml ${row.contents}`);
  if (row.type === 'diaper') bits.push([row.diaper, row.size, row.stool_color].filter(Boolean).join(' '));
  if (row.type === 'pump') bits.push(`L ${row.left_ml ?? 0} / R ${row.right_ml ?? 0} ml`);
  if (row.type === 'sleep') {
    bits.push(`${Math.round((Date.parse(row.ended_at) - Date.parse(row.started_at)) / 60000)} min`);
  }
  if (row.type === 'note') bits.push(row.note);
  return `${when} · ${KIND_LABEL[row.type]}${bits.length ? ' · ' + bits.join(' ') : ''}`;
}

function summarize(rows, timeZone) {
  const counts = {};
  for (const row of rows) counts[row.type] = (counts[row.type] ?? 0) + 1;
  const countText = Object.entries(counts).map(([kind, n]) => `${n} ${kind}`).join(', ') || 'nothing';
  const range = rows.length
    ? `${new Date(rows[0].started_at).toLocaleDateString('en-US', { timeZone, month: 'short', day: 'numeric' })} to ${new Date(rows.at(-1).started_at).toLocaleDateString('en-US', { timeZone, month: 'short', day: 'numeric', year: 'numeric' })}`
    : '';
  return { counts, countText, range };
}

function writeImportFile(rows, label, outputDir) {
  const dir = resolve(outputDir ?? defaultOutputDir());
  mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '');
  const path = join(dir, `Nested import ${label} ${stamp}.csv`);
  writeFileSync(path, toCsv(rows), 'utf8');
  return path;
}

const HOW_TO_APPLY = [
  'To bring it into Nest on the phone:',
  '1. Open the file from the Files app (iCloud Drive ▸ Nested Imports, or AirDrop it).',
  '2. In Nest: Settings ▸ Export and import ▸ Import from Nest CSV…, and pick it.',
  'Entries already logged at the same time are skipped, so importing twice is harmless.',
].join('\n');

/** Huckleberry export (xlsx or csv) -> Nest CSV file. */
export function importHuckleberryFile({ path, timezone, outputDir, dryRun = false }) {
  const timeZone = resolveTimeZone(timezone);
  const file = path.startsWith('~') ? join(homedir(), path.slice(1)) : resolve(path);
  const table = tableFromFile(readFileSync(file));
  const { rows, skipped, duplicates } = parseHuckleberry(table, timeZone);
  const { counts, countText, range } = summarize(rows, timeZone);

  const lines = [
    `Read ${rows.length} entries from ${file.split('/').at(-1)}: ${countText}.`,
    range && `Range: ${range} (times read in ${timeZone}).`,
    duplicates && `${duplicates} repeated rows were counted once.`,
    skipped.length && `Skipped ${skipped.length}: ${skipped.slice(0, 10).map((s) => `row ${s.line} (${s.reason})`).join('; ')}.`,
  ].filter(Boolean);

  let outputPath = null;
  if (!dryRun && rows.length) {
    outputPath = writeImportFile(rows, 'Huckleberry', outputDir);
    lines.push(`Wrote ${outputPath}`, '', HOW_TO_APPLY);
  } else if (dryRun) {
    lines.push('', 'Dry run: nothing was written.');
  }
  return { text: lines.join('\n'), counts, rows: rows.length, skipped, duplicates, path: outputPath };
}

/** Structured events (from text or screenshots) -> Nest CSV file. */
export function importEvents({ events, timezone, outputDir, dryRun = false, label = 'events' }) {
  const timeZone = resolveTimeZone(timezone);
  const parsed = events.map((event, i) => {
    const result = EventSchema.safeParse(event);
    return result.success ? { ok: result.data } : { error: `Event ${i + 1}: ${result.error.issues.map((x) => `${x.path.join('.') || 'event'} ${x.message}`).join('; ')}` };
  });
  const validationProblems = parsed.filter((p) => p.error).map((p) => p.error);
  const { rows, problems } = eventsToRows(parsed.filter((p) => p.ok).map((p) => p.ok), timeZone);
  const allProblems = [...validationProblems, ...problems];
  const { counts, countText, range } = summarize(rows, timeZone);

  const lines = [
    `${rows.length} of ${events.length} events are ready: ${countText}.`,
    range && `Range: ${range} (times read in ${timeZone}).`,
    ...rows.slice(0, 60).map((row) => `  ${describeRow(row, timeZone)}`),
    allProblems.length && `Problems (${allProblems.length}), not imported:\n${allProblems.map((p) => `  - ${p}`).join('\n')}`,
  ].filter(Boolean);

  let outputPath = null;
  if (!dryRun && rows.length) {
    outputPath = writeImportFile(rows, label.replace(/[^\w -]/g, '').slice(0, 40) || 'events', outputDir);
    lines.push('', `Wrote ${outputPath}`, '', HOW_TO_APPLY);
  } else if (dryRun) {
    lines.push('', 'Dry run: nothing was written. Show this to the person, fix anything wrong, then call again without dryRun.');
  }
  return { text: lines.join('\n'), counts, rows: rows.length, problems: allProblems, path: outputPath };
}

export const FORMAT_GUIDE = `# Nest import guide

Nest imports one CSV format (columns: ${HEADER.join(', ')}). You never write it by hand:
use the tools, which validate and convert.

## Sources
- **Huckleberry**: the person exports from Huckleberry (Child ▸ Reports ▸ "Export tracking data as CSV",
  emailed link; the file may be a real CSV or an Excel workbook). Call import_huckleberry_file with its path.
- **Nanit, other trackers, paper logs, screenshots, pasted text**: read the text or images yourself,
  write out each entry as a structured event, and call import_events with dryRun=true first. Show the
  person what you read (times especially) and let them correct it, then call again without dryRun.

## Nanit specifics
Nanit only records sleep (and night visits), not feeds or diapers. A night's sleep is one "sleep"
event from bedtime/fall-asleep to wake; the wake time is usually the next calendar day, so check the
date. Night visits (a parent entering the room) are not separate sleep; put them in a note event only if
the person wants them kept. Nanit's "Time Asleep" excludes awake periods, so prefer the actual start
and end times shown over durations.

## Rules for reading screenshots
- Every event needs a full date. If the screenshot shows only a time, ask which date, or infer from a
  visible date header and say what you assumed.
- Ask for the baby's timezone if the person isn't in their usual one; default is this computer's.
- Don't guess values you can't see (amounts, sides). Leave optional fields out, or ask.
- Sleep needs an end time. Bottles need an amount. Nursing needs minutes on a side or an end time.

## Event kinds
sleep(start,end,location?) · nursing(start,end?,leftMinutes?,rightMinutes?,endedOn?) ·
bottle(start,amountMl|amountOz,contents?) · diaper(time,diaper,stoolColor?,size?,consistency?,rash?) ·
pump(start,end?,leftMl|leftOz?,rightMl|rightOz?,destination?) · note(time,text,tag?)

## Getting it into the app
The tools write a CSV (to iCloud Drive/Nested Imports when available) that the person opens from the
Files app, then Nest ▸ Settings ▸ Export and import ▸ Import from Nest CSV…. Re-importing is harmless:
entries at the same time as existing ones are skipped.
`;
