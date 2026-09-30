import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { HEADER, parseTime, toCsv, zonedToInstant, isoUtc } from '../src/format.js';
import { parseHuckleberry, tableFromFile } from '../src/huckleberry.js';
import { importEvents, importHuckleberryFile } from '../src/importer.js';
import { createServer } from '../src/index.js';

const NY = 'America/New_York';
const fixture = (name) => join(import.meta.dirname, 'fixtures', name);

// The same synthetic export is tested against NestKit/Tests/NestDataTests/HuckleberryImportTests.swift.
function check(result) {
  const counts = {};
  for (const row of result.rows) counts[row.type] = (counts[row.type] ?? 0) + 1;
  assert.deepEqual(counts, { nursing: 3, bottle: 1, diaper: 3, sleep: 1, pump: 2, note: 1 });
  assert.equal(result.duplicates, 1);
  assert.deepEqual(result.skipped.map((s) => s.reason).sort(), ['bottle without an amount', 'sleep without an end time']);

  const both = result.rows.find((r) => r.type === 'nursing' && r.right_seconds === 24 * 60);
  assert.equal(both.left_seconds, 25 * 60);
  assert.equal(both.ended_on_side, 'left');
  assert.equal(Date.parse(both.ended_at) - Date.parse(both.started_at), 49 * 60000);

  const leftOnly = result.rows.find((r) => r.type === 'nursing' && r.left_seconds === 28 * 60);
  assert.equal(leftOnly.right_seconds, 0);

  const bottle = result.rows.find((r) => r.type === 'bottle');
  assert.equal(bottle.amount_ml, 20);
  assert.equal(bottle.contents, 'breastMilk');

  const poo = result.rows.find((r) => r.diaper === 'dirty');
  assert.equal(poo.stool_color, 'black');
  assert.equal(poo.size, 'medium');
  assert.equal(result.rows.find((r) => r.diaper === 'mixed').size, 'large');

  const ounces = result.rows.find((r) => r.type === 'pump' && r.right_ml === undefined);
  assert.ok(Math.abs(ounces.left_ml - 0.25 * 29.57) < 0.001);
  const pair = result.rows.find((r) => r.type === 'pump' && r.right_ml !== undefined);
  assert.deepEqual([pair.left_ml, pair.right_ml], [0, 20]);

  const note = result.rows.find((r) => r.type === 'note');
  assert.equal(note.note, 'Medication: Drops, Vitamin D, 1ml');
  assert.equal(note.tag, 'medicine');
}

test('Excel workbook', () => check(parseHuckleberry(tableFromFile(readFileSync(fixture('huckleberry-sample.xlsx'))), NY)));
test('Text CSV', () => check(parseHuckleberry(tableFromFile(readFileSync(fixture('huckleberry-sample.csv'))), NY)));

test('Both formats give identical rows', () => {
  const a = parseHuckleberry(tableFromFile(readFileSync(fixture('huckleberry-sample.xlsx'))), NY);
  const b = parseHuckleberry(tableFromFile(readFileSync(fixture('huckleberry-sample.csv'))), NY);
  assert.deepEqual(a.rows, b.rows);
});

test('Output matches the fixture the Swift importer also reads', () => {
  const { rows } = parseHuckleberry(tableFromFile(readFileSync(fixture('huckleberry-sample.csv'))), NY);
  const csv = toCsv(rows);
  assert.ok(csv.startsWith(HEADER.join(',') + '\r\n'));
  assert.equal(csv, readFileSync(fixture('expected-nest.csv'), 'utf8'));
});

test('Time zones and date styles', () => {
  // 6:05 PM in New York on 2026-09-28 (EDT, UTC-4) is 22:05Z; in winter it's UTC-5.
  for (const text of ['2026-09-28 18:05', '2026-09-28T18:05:00', '9/28/2026 18:05', '9/28/2026 6:05 PM']) {
    assert.equal(isoUtc(parseTime(text, NY)), '2026-09-28T22:05:00Z', text);
  }
  assert.equal(isoUtc(parseTime('2026-01-15T18:05', NY)), '2026-01-15T23:05:00Z');
  assert.equal(isoUtc(parseTime('2026-09-28T18:05:00-07:00', NY)), '2026-09-29T01:05:00Z');
  assert.equal(parseTime('nonsense', NY), null);
  // A wall-clock time that doesn't exist / repeats around DST still lands within an hour.
  assert.ok(Math.abs(zonedToInstant({ year: 2026, month: 3, day: 8, hour: 2, minute: 30 }, NY) - Date.UTC(2026, 2, 8, 7, 30)) <= 3600000);
});

test('Rejects files that are not Huckleberry exports', () => {
  assert.throws(() => parseHuckleberry([['a', 'b'], ['1', '2']], NY), /Huckleberry/);
});

test('Events from text or screenshots are validated and converted', () => {
  const dir = mkdtempSync(join(tmpdir(), 'nested-'));
  const result = importEvents({
    timezone: NY, outputDir: dir, label: 'Nanit nights',
    events: [
      { kind: 'sleep', start: '2026-09-27T20:12', end: '2026-09-28T05:40', location: 'crib' },
      { kind: 'bottle', start: '2026-09-28T06:00', amountOz: 3, contents: 'formula' },
      { kind: 'nursing', start: '2026-09-28T07:00', leftMinutes: 10, rightMinutes: 5, endedOn: 'right' },
      { kind: 'diaper', time: '2026-09-28T07:20', diaper: 'dirty', stoolColor: 'yellow', size: 'small' },
      { kind: 'pump', start: '2026-09-28T09:00', leftOz: 1, rightOz: 1.5 },
      { kind: 'note', time: '2026-09-28T09:30', text: 'Spit up after feed', tag: 'spitUp' },
      { kind: 'sleep', start: '2026-09-28T10:00', end: '2026-09-28T09:00' },
      { kind: 'sleep', start: 'yesterday-ish', end: '2026-09-28T09:00' },
      { kind: 'bottle', start: '2026-09-28T11:00' },
    ],
  });
  assert.equal(result.rows, 6);
  assert.equal(result.problems.length, 3);
  assert.match(result.text, /Nested import Nanit nights/);
  const csv = readFileSync(result.path, 'utf8').split('\r\n');
  assert.equal(csv[0], HEADER.join(','));
  const sleep = csv.find((line) => line.startsWith('sleep,'));
  assert.ok(sleep.startsWith('sleep,2026-09-28T00:12:00Z,2026-09-28T09:40:00Z'));
  const bottle = csv.find((line) => line.startsWith('bottle,'));
  assert.ok(bottle.includes(',88.7,'), bottle); // 3 oz
});

test('Dry runs write nothing', () => {
  const result = importEvents({ timezone: NY, dryRun: true, events: [{ kind: 'note', time: '2026-09-28T09:30', text: 'x' }] });
  assert.equal(result.path, null);
  assert.match(result.text, /Dry run/);
});

test('importHuckleberryFile writes a Nest CSV', () => {
  const dir = mkdtempSync(join(tmpdir(), 'nested-'));
  const result = importHuckleberryFile({ path: fixture('huckleberry-sample.xlsx'), timezone: NY, outputDir: dir });
  assert.equal(result.rows, 11);
  assert.match(readFileSync(result.path, 'utf8'), /^type,started_at/);
  assert.throws(() => importHuckleberryFile({ path: fixture('huckleberry-sample.xlsx'), timezone: 'Mars/Base' }), /Unknown timezone/);
});

test('The MCP server exposes its tools and runs them end to end', async () => {
  const server = createServer();
  const [clientSide, serverSide] = InMemoryTransport.createLinkedPair();
  const client = new Client({ name: 'test', version: '0' });
  await Promise.all([server.connect(serverSide), client.connect(clientSide)]);

  const { tools } = await client.listTools();
  assert.deepEqual(tools.map((t) => t.name).sort(), ['describe_import', 'import_events', 'import_huckleberry_file']);

  const guide = await client.callTool({ name: 'describe_import', arguments: {} });
  assert.match(guide.content[0].text, /Nanit/);

  const dir = mkdtempSync(join(tmpdir(), 'nested-'));
  const ok = await client.callTool({
    name: 'import_huckleberry_file',
    arguments: { path: fixture('huckleberry-sample.csv'), timezone: NY, outputDir: dir },
  });
  assert.ok(!ok.isError);
  assert.equal(ok.structuredContent.rows, 11);

  const bad = await client.callTool({ name: 'import_huckleberry_file', arguments: { path: '/no/such/file.csv' } });
  assert.equal(bad.isError, true);

  const events = await client.callTool({
    name: 'import_events',
    arguments: { timezone: NY, dryRun: true, events: [{ kind: 'diaper', time: '2026-09-28T07:20', diaper: 'wet' }] },
  });
  assert.equal(events.structuredContent.rows, 1);

  await client.close();
});
