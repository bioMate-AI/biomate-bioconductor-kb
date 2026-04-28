/**
 * Hardcoded string extractor.
 *
 * Scans the BioMate frontend source for patterns that look like
 * hardcoded UI strings that should be replaced with t('key') calls.
 *
 * Usage:
 *   npx tsx scripts/extract-strings.ts [--frontend-dir <path>]
 *
 * Output:
 *   - Summary table of files with the most hardcoded strings
 *   - Candidate strings grouped by category
 */

import { readFileSync, readdirSync, statSync } from 'fs';
import { resolve, extname, relative } from 'path';

const FRONTEND_DIR = resolve(
  process.argv[process.argv.indexOf('--frontend-dir') + 1] ||
  '../../frontend/client/src'
);

// Patterns that suggest hardcoded UI text (not scientific terms)
const PATTERNS = [
  // JSX string children: >Loading...</  or > Loading... <
  { name: 'JSX text content', regex: />([A-Z][a-z][\w\s.,!?]{4,60})</g },
  // placeholder="..."
  { name: 'placeholder attribute', regex: /placeholder=["']([^"']{4,80})["']/g },
  // title="..."
  { name: 'title attribute', regex: /title=["']([^"']{4,60})["']/g },
  // aria-label="..."
  { name: 'aria-label attribute', regex: /aria-label=["']([^"']{4,60})["']/g },
  // Button/span text: common UI action words
  { name: 'action button text', regex: /["'](Run|Cancel|Submit|Save|Delete|Upload|Download|Create|Confirm|Close|Back|Next|Search|Filter|Reset|Retry|Skip|Edit|View|Refresh)["']/g },
];

// Words to exclude (scientific terms, code values, etc.)
const EXCLUDE_PATTERNS = [
  /^\d/, /^https?:\/\//, /^\//, /^\$\{/, /^#/, /^[A-Z_]{3,}$/,
  /^[a-z-]+$/, // likely a class name or identifier
  /SMILES|FASTA|PDB|SRA|VCF|BAM|SAM|GTF|GFF/i,
];

function shouldExclude(str: string): boolean {
  return EXCLUDE_PATTERNS.some(p => p.test(str));
}

function walkDir(dir: string, exts: string[] = ['.tsx', '.ts']): string[] {
  const results: string[] = [];
  try {
    for (const entry of readdirSync(dir)) {
      const full = resolve(dir, entry);
      const stat = statSync(full);
      if (stat.isDirectory() && !entry.startsWith('.') && entry !== 'node_modules') {
        results.push(...walkDir(full, exts));
      } else if (stat.isFile() && exts.includes(extname(entry))) {
        results.push(full);
      }
    }
  } catch { /* skip inaccessible dirs */ }
  return results;
}

interface Finding {
  file: string;
  pattern: string;
  match: string;
  line: number;
}

function extractFromFile(filePath: string): Finding[] {
  const content = readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');
  const findings: Finding[] = [];
  const relPath = relative(FRONTEND_DIR, filePath);

  for (const { name, regex } of PATTERNS) {
    regex.lastIndex = 0;
    let match: RegExpExecArray | null;
    while ((match = regex.exec(content)) !== null) {
      const str = match[1]?.trim();
      if (!str || str.length < 3 || shouldExclude(str)) continue;
      // Find line number
      const upTo = content.slice(0, match.index);
      const lineNum = upTo.split('\n').length;
      findings.push({ file: relPath, pattern: name, match: str, line: lineNum });
    }
    regex.lastIndex = 0;
  }
  return findings;
}

// Run extraction
console.log(`Scanning: ${FRONTEND_DIR}\n`);
const files = walkDir(FRONTEND_DIR);
const allFindings: Finding[] = [];

for (const file of files) {
  allFindings.push(...extractFromFile(file));
}

// Deduplicate by match string
const unique = new Map<string, Finding>();
for (const f of allFindings) {
  if (!unique.has(f.match)) unique.set(f.match, f);
}

// Group by pattern type
const byPattern = new Map<string, Finding[]>();
for (const f of unique.values()) {
  const arr = byPattern.get(f.pattern) ?? [];
  arr.push(f);
  byPattern.set(f.pattern, arr);
}

// Files with most hits
const fileHits = new Map<string, number>();
for (const f of allFindings) {
  fileHits.set(f.file, (fileHits.get(f.file) ?? 0) + 1);
}
const topFiles = [...fileHits.entries()].sort((a, b) => b[1] - a[1]).slice(0, 15);

console.log('=== Top files by hardcoded string count ===');
for (const [file, count] of topFiles) {
  console.log(`  ${count.toString().padStart(3)}  ${file}`);
}

console.log('\n=== Candidate strings by pattern ===');
for (const [pattern, findings] of byPattern) {
  console.log(`\n[${pattern}] — ${findings.length} unique strings`);
  for (const f of findings.slice(0, 20)) {
    console.log(`  "${f.match}"  (${f.file}:${f.line})`);
  }
  if (findings.length > 20) console.log(`  ... and ${findings.length - 20} more`);
}

console.log(`\nTotal unique candidate strings: ${unique.size}`);
console.log(`Total files scanned: ${files.length}`);
