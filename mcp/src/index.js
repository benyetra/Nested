#!/usr/bin/env node
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { EventSchema } from './events.js';
import { FORMAT_GUIDE, importEvents, importHuckleberryFile } from './importer.js';

export function createServer() {
  const server = new McpServer({ name: 'nested', version: '0.1.0' });

  const reply = (result) => ({
    content: [{ type: 'text', text: result.text }],
    structuredContent: { rows: result.rows, counts: result.counts, path: result.path ?? null },
  });
  const failure = (error) => ({
    isError: true,
    content: [{ type: 'text', text: `Import failed: ${error instanceof Error ? error.message : String(error)}` }],
  });

  server.registerTool(
    'import_huckleberry_file',
    {
      title: 'Import a Huckleberry export',
      description:
        "Reads a Huckleberry data export (.csv or Excel .xlsx, from Child ▸ Reports ▸ Export tracking data as CSV) and writes a Nest import file with feeds, bottles, diapers, sleep and pumping. Repeated rows are collapsed. Set dryRun to preview counts without writing.",
      inputSchema: {
        path: z.string().describe('Path to the exported file on this computer.'),
        timezone: z.string().optional().describe("The baby's IANA timezone (e.g. America/New_York). Defaults to this computer's."),
        outputDir: z.string().optional().describe('Folder for the Nest import file. Defaults to iCloud Drive/Nested Imports.'),
        dryRun: z.boolean().optional(),
      },
      annotations: { readOnlyHint: false, idempotentHint: true, openWorldHint: false },
    },
    async (args) => {
      try {
        return reply(importHuckleberryFile(args));
      } catch (error) {
        return failure(error);
      }
    }
  );

  server.registerTool(
    'import_events',
    {
      title: 'Import events read from text or screenshots',
      description:
        "Turns entries you read from text or screenshots (Nanit sleep summaries, another tracker, a paper log) into a Nest import file. Call describe_import first if unsure how to read a source. Use dryRun=true first and show the person what you read, especially dates and times, then call again without dryRun to write the file.",
      inputSchema: {
        events: z.array(EventSchema).min(1).max(1000),
        timezone: z.string().optional().describe("The baby's IANA timezone. Defaults to this computer's."),
        label: z.string().optional().describe('Short name for the file, e.g. "Nanit nights".'),
        outputDir: z.string().optional(),
        dryRun: z.boolean().optional(),
      },
      annotations: { readOnlyHint: false, idempotentHint: true, openWorldHint: false },
    },
    async (args) => {
      try {
        return reply(importEvents(args));
      } catch (error) {
        return failure(error);
      }
    }
  );

  server.registerTool(
    'describe_import',
    {
      title: 'How importing into Nest works',
      description:
        'Explains the import sources, how to read Nanit and other screenshots into events, the event fields, and how the file gets into the app. Call this before importing from screenshots or text.',
      inputSchema: {},
      annotations: { readOnlyHint: true },
    },
    async () => ({ content: [{ type: 'text', text: FORMAT_GUIDE }] })
  );

  return server;
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  await createServer().connect(new StdioServerTransport());
}
