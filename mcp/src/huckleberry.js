import { readFirstSheet, looksLikeZip } from './xlsx.js';
import { ML_PER_OUNCE, isoUtc, parseTime } from './format.js';

// Mirror of NestedKit/Sources/NestedCore/HuckleberryImport.swift. Keep the two in step: the same
// synthetic export is tested against both.

export function parseCsvText(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else quoted = false;
      } else field += c;
      continue;
    }
    if (c === '"') quoted = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\r' || c === '\n') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(field); field = '';
      if (!(row.length === 1 && row[0] === '')) rows.push(row);
      row = [];
    } else field += c;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  return rows;
}

/** Reads a Huckleberry export from file bytes (Excel workbook or CSV text). */
export function tableFromFile(buffer) {
  if (looksLikeZip(buffer)) return readFirstSheet(buffer);
  let text = buffer.toString('utf8');
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  return parseCsvText(text);
}

const amountMl = (text) => {
  const m = String(text).toLowerCase().replace(/\s/g, '').match(/^([\d.]+)(ml|oz)$/);
  if (!m) return null;
  const value = Number(m[1]);
  return m[2] === 'oz' ? value * ML_PER_OUNCE : value;
};

// "00:24R" -> ['right', 1440]. The digits are hours and minutes.
function sideSegment(text) {
  const m = String(text).trim().match(/^(\d+):(\d{1,2})\s*([LRlr])$/);
  if (!m) return null;
  return [m[3].toUpperCase() === 'L' ? 'left' : 'right', Number(m[1]) * 3600 + Number(m[2]) * 60];
}

const STOOL = [
  ['dark green', 'darkGreen'], ['mustard', 'mustardYellow'], ['yellow', 'yellow'], ['green', 'green'],
  ['black', 'black'], ['brown', 'brown'], ['orange', 'orange'], ['red', 'red'], ['pale', 'pale'],
  ['white', 'pale'], ['clay', 'pale'], ['gray', 'pale'], ['grey', 'pale'],
];
const CONSISTENCY = [
  ['runny', 'runny'], ['watery', 'runny'], ['seedy', 'seedy'], ['pasty', 'pasty'],
  ['formed', 'formed'], ['hard', 'hard'], ['mucous', 'mucousy'],
];
const firstMatch = (table, text) => table.find(([word]) => text.includes(word))?.[1];

function diaperSize(text) {
  for (const key of ['poo:', 'pee:', '']) {
    const scope = key ? (text.split(key)[1] ?? '') : text;
    for (const size of ['small', 'medium', 'large']) if (scope.startsWith(size)) return size;
  }
  for (const size of ['small', 'medium', 'large']) if (text.includes(size)) return size;
  return undefined;
}

function durationSeconds(text) {
  const days = Number(text);
  if (text && Number.isFinite(days) && days > 0 && days < 2) return days * 86400;
  const m = String(text).match(/^(\d+):(\d{2})$/);
  return m ? Number(m[1]) * 3600 + Number(m[2]) * 60 : null;
}

/**
 * Turns a table (header + rows) from a Huckleberry export into Nested CSV rows.
 * Returns { rows, skipped: [{line, reason}], duplicates }.
 */
export function parseHuckleberry(table, timeZone) {
  const header = (table[0] ?? []).map((h) => h.trim().toLowerCase());
  const at = (name) => header.indexOf(name);
  if (at('type') < 0 || at('start') < 0) {
    throw new Error("This doesn't look like a Huckleberry export. It needs Type and Start columns.");
  }

  const rows = [];
  const skipped = [];
  const seen = new Set();
  let duplicates = 0;

  table.slice(1).forEach((fields, offset) => {
    const line = offset + 2;
    const cell = (name) => (at(name) >= 0 ? (fields[at(name)] ?? '').trim() : '');
    const type = cell('type');
    if (!type) return;

    const start = parseTime(cell('start'), timeZone);
    if (start === null) return skipped.push({ line, reason: `unreadable start time '${cell('start')}'` });
    const end = parseTime(cell('end'), timeZone);
    const r = {
      duration: cell('duration'), startCondition: cell('start condition'),
      startLocation: cell('start location'), endCondition: cell('end condition'),
      notes: cell('notes'), loggedBy: cell('logged by'),
    };
    const base = (kind) => ({
      type: kind, started_at: isoUtc(start), ended_at: end === null ? '' : isoUtc(end),
      note: r.notes, logged_by: r.loggedBy, time_zone: timeZone,
    });
    const everything = [r.duration, r.startCondition, r.startLocation, r.endCondition, r.notes];

    let row;
    const lower = type.toLowerCase();
    if (lower === 'sleep') {
      if (end === null) return skipped.push({ line, reason: 'sleep without an end time' });
      if (end <= start) return skipped.push({ line, reason: 'sleep ends before it starts' });
      row = base('sleep');
    } else if (lower === 'feed' && r.startLocation.toLowerCase().includes('bottle')) {
      const ml = amountMl(r.endCondition) ?? amountMl(r.startCondition);
      if (ml === null) return skipped.push({ line, reason: 'bottle without an amount' });
      const contents = r.startCondition.toLowerCase();
      const breast = contents.includes('breast');
      const formula = contents.includes('formula');
      row = { ...base('bottle'), ended_at: '', amount_ml: ml, contents: breast && formula ? 'mixed' : breast ? 'breastMilk' : 'formula' };
    } else if (lower === 'feed' && (r.startLocation === '' || r.startLocation.toLowerCase().includes('breast'))) {
      const totals = { left: 0, right: 0 };
      let last = null;
      for (const text of [r.startCondition, r.endCondition]) {
        const segment = sideSegment(text);
        if (segment) { totals[segment[0]] += segment[1]; last = segment[0]; }
      }
      if (!last) return skipped.push({ line, reason: 'breast feed without side times' });
      row = { ...base('nursing'), left_seconds: totals.left, right_seconds: totals.right, ended_on_side: last };
      if (end === null) row.ended_at = isoUtc(start + (totals.left + totals.right) * 1000);
    } else if (lower === 'diaper') {
      const kindText = ([r.endCondition, r.startCondition].find((t) => t) ?? '').toLowerCase();
      const pee = kindText.includes('pee') || kindText.includes('wet');
      const poo = kindText.includes('poo') || kindText.includes('dirty') || kindText.includes('stool');
      const both = kindText.includes('both') || kindText.includes('mixed');
      const kind = both || (pee && poo) ? 'mixed' : poo ? 'dirty' : pee ? 'wet'
        : kindText.includes('dry') || kindText.includes('clean') ? 'dry' : null;
      if (!kind) return skipped.push({ line, reason: 'diaper without a type' });
      row = { ...base('diaper'), ended_at: '', diaper: kind, size: diaperSize(kindText) };
      if (kind === 'dirty' || kind === 'mixed') {
        const words = everything.join(' ').toLowerCase();
        row.stool_color = firstMatch(STOOL, words);
        row.consistency = firstMatch(CONSISTENCY, words);
      }
      if (everything.some((t) => t.toLowerCase().includes('rash'))) row.rash = 'true';
    } else if (lower === 'pump') {
      const first = amountMl(r.startCondition);
      const second = amountMl(r.endCondition);
      if (first === null && second === null) return skipped.push({ line, reason: 'pump without an amount' });
      row = { ...base('pump'), left_ml: second !== null ? (first ?? 0) : first };
      if (second !== null) row.right_ml = second;
    } else {
      const parts = [r.startLocation, r.startCondition, r.endCondition].filter(Boolean);
      const seconds = durationSeconds(r.duration);
      if (seconds !== null && seconds >= 60) parts.push(`${Math.round(seconds / 60)} min`);
      else if (r.duration && Number.isNaN(Number(r.duration))) parts.push(r.duration);
      if (r.notes) parts.push(r.notes);
      row = {
        ...base('note'), ended_at: '',
        note: parts.length ? `${type}: ${parts.join(', ')}` : type,
      };
      if (lower.includes('medic')) row.tag = 'medicine';
      if (lower.includes('temp')) row.tag = 'temperature';
    }

    const key = JSON.stringify(row);
    if (seen.has(key)) duplicates++;
    else { seen.add(key); rows.push(row); }
  });

  rows.sort((a, b) => a.started_at.localeCompare(b.started_at));
  return { rows, skipped, duplicates };
}
