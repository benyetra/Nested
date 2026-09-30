// Nested's CSV import format (see NestedKit/Sources/NestedCore/CSV.swift `EntryRow`). The app's
// importer skips anything already logged at the same time, so re-importing is harmless.

export const HEADER = [
  'type', 'started_at', 'ended_at', 'amount_ml', 'offered_ml', 'contents', 'formula_brand',
  'left_seconds', 'right_seconds', 'ended_on_side', 'left_ml', 'right_ml', 'destination',
  'diaper', 'stool_color', 'consistency', 'size', 'rash', 'location', 'tag', 'note',
  'logged_by', 'time_zone',
];

export const ML_PER_OUNCE = 29.57;

function escapeField(value) {
  const text = value === undefined || value === null ? '' : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

function numberText(value) {
  if (value === undefined || value === null) return '';
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

/** Rows are plain objects keyed by HEADER names. */
export function toCsv(rows) {
  const numeric = new Set(['amount_ml', 'offered_ml', 'left_seconds', 'right_seconds', 'left_ml', 'right_ml']);
  const lines = [HEADER.join(',')];
  for (const row of rows) {
    lines.push(
      HEADER.map((column) =>
        escapeField(numeric.has(column) ? numberText(row[column]) : row[column])
      ).join(',')
    );
  }
  return lines.join('\r\n') + '\r\n';
}

// MARK: Time zones

export function systemTimeZone() {
  return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
}

export function isValidTimeZone(tz) {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

function offsetMs(instant, timeZone) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone, hourCycle: 'h23', year: 'numeric', month: 'numeric', day: 'numeric',
    hour: 'numeric', minute: 'numeric', second: 'numeric',
  }).formatToParts(new Date(instant));
  const get = (type) => Number(parts.find((p) => p.type === type).value);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
  return asUtc - Math.floor(instant / 1000) * 1000;
}

/** Wall-clock components in `timeZone` -> an instant (ms since epoch). */
export function zonedToInstant({ year, month, day, hour = 0, minute = 0, second = 0 }, timeZone) {
  const guess = Date.UTC(year, month - 1, day, hour, minute, second);
  let instant = guess - offsetMs(guess, timeZone);
  instant = guess - offsetMs(instant, timeZone);
  return instant;
}

export function isoUtc(instant) {
  return new Date(instant).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

/**
 * Parses a time from a person, a spreadsheet or a model. Accepts ISO 8601 (with or without an
 * offset), "2026-09-28 18:05", "9/28/2026 6:05 PM", and Excel serial numbers. Times without an
 * offset are wall-clock time in `timeZone`. Returns an instant (ms) or null.
 */
export function parseTime(raw, timeZone) {
  const text = String(raw ?? '').trim();
  if (!text) return null;

  if (/^\d+(\.\d+)?$/.test(text) && Number(text) > 20000 && Number(text) < 80000) {
    const serial = Number(text);
    const whole = Math.floor(serial);
    const minutes = Math.round((serial - whole) * 1440);
    const wall = new Date(Date.UTC(1899, 11, 30) + whole * 86400000 + minutes * 60000);
    return zonedToInstant(
      {
        year: wall.getUTCFullYear(), month: wall.getUTCMonth() + 1, day: wall.getUTCDate(),
        hour: wall.getUTCHours(), minute: wall.getUTCMinutes(),
      },
      timeZone
    );
  }

  let match = text.match(/^(\d{4})-(\d{2})-(\d{2})[T ](\d{1,2}):(\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:?\d{2})?$/i);
  if (match) {
    const [, y, mo, d, h, mi, s, zone] = match;
    if (zone) return Date.parse(`${y}-${mo}-${d}T${h.padStart(2, '0')}:${mi}:${s ?? '00'}${zone.length === 5 && zone[3] !== ':' ? zone.slice(0, 3) + ':' + zone.slice(3) : zone}`);
    return zonedToInstant(
      { year: +y, month: +mo, day: +d, hour: +h, minute: +mi, second: +(s ?? 0) }, timeZone);
  }

  match = text.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2,4}),?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?$/i);
  if (match) {
    let [, mo, d, y, h, mi, s, ampm] = match;
    y = +y < 100 ? 2000 + +y : +y;
    h = +h;
    if (ampm) {
      const pm = ampm.toUpperCase() === 'PM';
      if (pm && h < 12) h += 12;
      if (!pm && h === 12) h = 0;
    }
    return zonedToInstant({ year: y, month: +mo, day: +d, hour: h, minute: +mi, second: +(s ?? 0) }, timeZone);
  }

  return null;
}
