import { z } from 'zod';
import { ML_PER_OUNCE, isoUtc, parseTime } from './format.js';

// Structured events, for data a person pastes as text or screenshots (Nanit, a paper log,
// another tracker). The model reads the text or image and fills these in; this module checks
// them and turns them into Nested CSV rows.

const time = z
  .string()
  .describe(
    'Local time like "2026-09-28T18:05" (read in the timezone argument), or with an offset like "2026-09-28T18:05:00-04:00". Always include the date.'
  );

const common = {
  note: z.string().optional().describe('Free text to keep with the entry.'),
  loggedBy: z.string().optional().describe('Who logged it, if the source says.'),
};

export const EventSchema = z.discriminatedUnion('kind', [
  z.object({
    kind: z.literal('sleep'),
    start: time,
    end: time.describe('When she woke. Sleep without an end time is rejected.'),
    location: z.enum(['crib', 'bassinet', 'arms', 'stroller', 'car']).optional(),
    ...common,
  }),
  z.object({
    kind: z.literal('nursing'),
    start: time,
    end: time.optional(),
    leftMinutes: z.number().nonnegative().optional(),
    rightMinutes: z.number().nonnegative().optional(),
    endedOn: z.enum(['left', 'right']).optional().describe('Last side; defaults to the side with time, right if both.'),
    ...common,
  }),
  z.object({
    kind: z.literal('bottle'),
    start: time,
    amountMl: z.number().positive().optional(),
    amountOz: z.number().positive().optional(),
    contents: z.enum(['breastMilk', 'formula', 'mixed']).optional(),
    ...common,
  }),
  z.object({
    kind: z.literal('diaper'),
    time,
    diaper: z.enum(['wet', 'dirty', 'mixed', 'dry']),
    stoolColor: z
      .enum(['black', 'darkGreen', 'green', 'mustardYellow', 'yellow', 'brown', 'orange', 'red', 'pale'])
      .optional(),
    consistency: z.enum(['runny', 'seedy', 'pasty', 'formed', 'hard', 'mucousy']).optional(),
    size: z.enum(['small', 'medium', 'large']).optional(),
    rash: z.boolean().optional(),
    ...common,
  }),
  z.object({
    kind: z.literal('pump'),
    start: time,
    end: time.optional(),
    leftMl: z.number().nonnegative().optional(),
    rightMl: z.number().nonnegative().optional(),
    leftOz: z.number().nonnegative().optional(),
    rightOz: z.number().nonnegative().optional(),
    destination: z.enum(['fedNow', 'fridge', 'freezer']).optional(),
    ...common,
  }),
  z.object({
    kind: z.literal('note'),
    time,
    text: z.string().min(1),
    tag: z.enum(['spitUp', 'fussy', 'medicine', 'temperature']).optional(),
    ...common,
  }),
]);

/** Returns { rows, problems } for validated events. Never throws on bad data; reports it. */
export function eventsToRows(events, timeZone) {
  const rows = [];
  const problems = [];
  events.forEach((event, i) => {
    const label = `Event ${i + 1} (${event.kind})`;
    const startText = event.kind === 'diaper' || event.kind === 'note' ? event.time : event.start;
    const start = parseTime(startText, timeZone);
    if (start === null) return problems.push(`${label}: can't read the time '${startText}'.`);
    const end = 'end' in event && event.end ? parseTime(event.end, timeZone) : null;
    if ('end' in event && event.end && end === null) return problems.push(`${label}: can't read the end time '${event.end}'.`);
    if (end !== null && end < start) return problems.push(`${label}: ends before it starts.`);

    const row = {
      type: event.kind, started_at: isoUtc(start), ended_at: end === null ? '' : isoUtc(end),
      note: event.note ?? '', logged_by: event.loggedBy ?? '', time_zone: timeZone,
    };
    switch (event.kind) {
      case 'sleep':
        if (end === null) return problems.push(`${label}: needs an end time.`);
        row.location = event.location;
        break;
      case 'nursing': {
        const left = (event.leftMinutes ?? 0) * 60;
        const right = (event.rightMinutes ?? 0) * 60;
        if (left + right <= 0 && end === null) return problems.push(`${label}: needs minutes on a side, or an end time.`);
        const total = left + right || (end - start) / 1000;
        // With no per-side split, put the whole feed on one side rather than inventing a split.
        const side = event.endedOn ?? (left > 0 && right === 0 ? 'left' : 'right');
        row.left_seconds = left + right > 0 ? left : side === 'left' ? total : 0;
        row.right_seconds = left + right > 0 ? right : side === 'right' ? total : 0;
        row.ended_on_side = side;
        if (end === null) row.ended_at = isoUtc(start + total * 1000);
        break;
      }
      case 'bottle': {
        const ml = event.amountMl ?? (event.amountOz !== undefined ? event.amountOz * ML_PER_OUNCE : undefined);
        if (ml === undefined) return problems.push(`${label}: needs amountMl or amountOz.`);
        row.amount_ml = Math.round(ml * 10) / 10;
        row.contents = event.contents ?? 'formula';
        row.ended_at = '';
        break;
      }
      case 'diaper':
        row.diaper = event.diaper;
        row.ended_at = '';
        if (event.diaper === 'dirty' || event.diaper === 'mixed') {
          row.stool_color = event.stoolColor;
          row.consistency = event.consistency;
        }
        row.size = event.size;
        if (event.rash) row.rash = 'true';
        break;
      case 'pump': {
        const left = event.leftMl ?? (event.leftOz !== undefined ? event.leftOz * ML_PER_OUNCE : undefined);
        const right = event.rightMl ?? (event.rightOz !== undefined ? event.rightOz * ML_PER_OUNCE : undefined);
        if (left === undefined && right === undefined) return problems.push(`${label}: needs an amount.`);
        row.left_ml = left === undefined ? undefined : Math.round(left * 10) / 10;
        row.right_ml = right === undefined ? undefined : Math.round(right * 10) / 10;
        row.destination = event.destination;
        break;
      }
      case 'note':
        row.note = [event.text, event.note].filter(Boolean).join(' ');
        row.tag = event.tag;
        row.ended_at = '';
        break;
    }
    rows.push(row);
  });
  rows.sort((a, b) => a.started_at.localeCompare(b.started_at));
  return { rows, problems };
}
