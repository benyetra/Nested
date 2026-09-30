# Nested MCP

An MCP server that helps bring history into Nest from other apps.

- **`import_huckleberry_file`** reads a Huckleberry export (CSV or Excel) and writes a Nest import file.
- **`import_events`** takes entries Claude read from **text or screenshots** (Nanit sleep summaries,
  another tracker, a paper log), checks them, and writes the same kind of file. It has a dry run, so
  Claude shows you what it read (dates and times especially) before anything is written.
- **`describe_import`** tells Claude how to read each source (including Nanit) and what the fields are.

The MCP never touches your data directly. It writes a CSV, and you import it in the app, which
skips anything already logged at the same time, so importing twice is harmless.

## Set up

Needs Node 20 or later. It runs on the computer where you use Claude.

```sh
cd mcp && npm install
```

**Claude Desktop** (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "nested": { "command": "node", "args": ["/Users/you/Development/Nested/mcp/src/index.js"] }
  }
}
```

**Claude Code**: `claude mcp add nested -- node /Users/you/Development/Nested/mcp/src/index.js`

Optional environment: `NESTED_IMPORT_DIR` sets where import files are written. By default that is
iCloud Drive ▸ `Nested Imports` (so the file shows up in the Files app on your phone), then
`~/Downloads/Nested Imports`.

## Using it

**Huckleberry.** In Huckleberry: Child ▸ Reports ▸ "Export tracking data as CSV". They email a link
(valid 24 hours). Then ask Claude: *"Import ~/Downloads/huckleberry.csv into Nested."* Or skip the MCP and
use Nest ▸ Settings ▸ Export and import ▸ Import from Huckleberry…, which reads the same file.

**Nanit and other apps.** Send Claude the screenshots or paste the text: *"Import these Nanit nights
into Nested."* Claude reads them and previews the entries. Correct anything wrong, and it writes the file.
Nanit records sleep only, so that is all that comes across.

**Into the app.** Open the file from Files (iCloud Drive ▸ Nested Imports), then Nest ▸ Settings ▸
Export and import ▸ Import from Nest CSV…

## Development

```sh
npm test
```

The Huckleberry mapping exists twice: here (`src/huckleberry.js`) and in the app
(`NestKit/Sources/NestCore/HuckleberryImport.swift`). The same synthetic export is tested against
both, and the Swift tests also read this server's output, so the two stay in step. Change one, change the other.
