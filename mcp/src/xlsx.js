import { inflateRawSync } from 'node:zlib';

// Just enough of ZIP and SpreadsheetML to read the first sheet of a workbook as strings.

export function looksLikeZip(buffer) {
  return buffer.length > 4 && buffer.readUInt32LE(0) === 0x04034b50;
}

function zipEntries(buffer) {
  let eocd = -1;
  for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 22 - 65535); i--) {
    if (buffer.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error('Not a zip file.');
  const count = buffer.readUInt16LE(eocd + 10);
  let cursor = buffer.readUInt32LE(eocd + 16);
  const entries = new Map();
  for (let n = 0; n < count; n++) {
    if (buffer.readUInt32LE(cursor) !== 0x02014b50) throw new Error('Damaged zip directory.');
    const method = buffer.readUInt16LE(cursor + 10);
    const size = buffer.readUInt32LE(cursor + 20);
    const nameLength = buffer.readUInt16LE(cursor + 28);
    const extraLength = buffer.readUInt16LE(cursor + 30);
    const commentLength = buffer.readUInt16LE(cursor + 32);
    const offset = buffer.readUInt32LE(cursor + 42);
    const name = buffer.toString('utf8', cursor + 46, cursor + 46 + nameLength);
    entries.set(name, { method, size, offset });
    cursor += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

function entryText(buffer, entries, name) {
  const entry = entries.get(name);
  if (!entry) return null;
  const start = entry.offset + 30 + buffer.readUInt16LE(entry.offset + 26) + buffer.readUInt16LE(entry.offset + 28);
  const raw = buffer.subarray(start, start + entry.size);
  if (entry.method === 0) return raw.toString('utf8');
  if (entry.method === 8) return inflateRawSync(raw).toString('utf8');
  throw new Error('Unsupported zip compression.');
}

const unescapeXml = (text) =>
  text.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&amp;/g, '&');

function blocks(tag, xml) {
  const result = [];
  const pattern = new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</${tag}>`, 'g');
  let match;
  while ((match = pattern.exec(xml))) result.push(match[1]);
  return result;
}

const textOf = (xml) => unescapeXml(blocks('t', xml).join(''));

function columnIndex(reference) {
  let column = 0;
  for (const ch of reference.replace(/\d/g, '')) column = column * 26 + (ch.charCodeAt(0) - 64);
  return column - 1;
}

/** First sheet as an array of rows of strings (numbers come through as raw text). */
export function readFirstSheet(buffer) {
  const entries = zipEntries(buffer);
  const sheetName = [...entries.keys()]
    .filter((name) => /^xl\/worksheets\/sheet\d*\.xml$/.test(name))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))[0];
  if (!sheetName) throw new Error('The workbook has no sheets.');
  const shared = blocks('si', entryText(buffer, entries, 'xl/sharedStrings.xml') ?? '').map(textOf);

  const xml = entryText(buffer, entries, sheetName);
  const rows = new Map();
  let maxColumn = 0;
  const cell = /<c\s([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g;
  let match;
  while ((match = cell.exec(xml))) {
    const attributes = match[1];
    const ref = attributes.match(/\br="([A-Z]+)(\d+)"/);
    if (!ref) continue;
    const type = attributes.match(/\bt="([^"]*)"/)?.[1];
    const body = match[2] ?? '';
    let value = '';
    if (type === 'inlineStr') {
      value = textOf(body);
    } else {
      const v = blocks('v', body)[0];
      if (v !== undefined) {
        value = type === 's' ? (shared[Number(v)] ?? '') : unescapeXml(v);
      }
    }
    const column = columnIndex(ref[1]);
    const row = Number(ref[2]);
    if (!rows.has(row)) rows.set(row, new Map());
    rows.get(row).set(column, value);
    maxColumn = Math.max(maxColumn, column);
  }
  return [...rows.keys()]
    .sort((a, b) => a - b)
    .map((row) => Array.from({ length: maxColumn + 1 }, (_, c) => rows.get(row).get(c) ?? ''));
}
