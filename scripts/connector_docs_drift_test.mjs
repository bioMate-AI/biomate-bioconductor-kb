#!/usr/bin/env node
/**
 * Guard connector-facing documentation against manifest drift.
 *
 * The public client surfaces do not all carry a generated schema, so a manifest
 * change used to leave installation/docs pages describing a smaller tool set.
 * This deliberately checks only the canonical overview pages; detailed tool
 * schemas remain protected by backend/tests/test_tools_manifest.py.
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const manifest = JSON.parse(readFileSync(join(root, 'backend/lib/mcp/tools_manifest.json'), 'utf8'));
const names = manifest.backend_routes.map((route) => route.name);
const count = names.length;
const docs = [
  'connectors/README.md',
  'connectors/claude-code/README.md',
  'connectors/installer/README.md',
  'connectors/chatgpt/README.md',
  'connectors/chatgpt/INSTALL.md',
  'connectors/codex/README.md',
  'connectors/open-claw/README.md',
  'connectors/slack/README.md',
].map((relative) => ({ relative, text: readFileSync(join(root, relative), 'utf8') }));

const failures = [];
// CI/release jobs should point this at the unpacked npm tarball's manifest.
// Comparing only repository copies misses package releases with extra tools.
if (process.env.CONNECTOR_PACKAGE_MANIFEST) {
  const published = JSON.parse(readFileSync(process.env.CONNECTOR_PACKAGE_MANIFEST, 'utf8'));
  const publishedNames = published.mcp.map(tool => tool.name);
  for (const name of publishedNames) {
    if (!names.includes(name)) failures.push(`published package: unsupported tool ${name}`);
  }
  for (const name of names) {
    if (!publishedNames.includes(name)) failures.push(`published package: missing tool ${name}`);
  }
  if (new Set(publishedNames).size !== publishedNames.length) failures.push('published package: duplicate tool names');
}
for (const { relative, text } of docs) {
  if (/\b14(?:-tool| tools?)\b/i.test(text)) failures.push(`${relative}: stale 14-tool claim`);
  if (!new RegExp(`\\b${count}(?:-tool|\\s+(?:MCP|connector)?\\s*tools?)\\b`, 'i').test(text)) {
    failures.push(`${relative}: does not state current ${count}-tool surface`);
  }
}

const central = docs.find((doc) => doc.relative === 'connectors/claude-code/README.md');
for (const name of names) {
  if (!central.text.includes(`\`${name}\``)) failures.push(`connectors/claude-code/README.md: missing ${name}`);
}

if (failures.length) {
  console.error(`connector documentation drift (${count} manifest tools):\n- ${failures.join('\n- ')}`);
  process.exit(1);
}
console.log(`connector documentation matches ${count}-tool manifest`);
