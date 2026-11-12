import { afterEach, describe, expect, it } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { scanOutputDir, snapshotDir } from './code-runner';

const dirs: string[] = [];
afterEach(() => { for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });

describe('run_code new-output detection is by content (founder: more files saved than the chat listed)', () => {
  it('a replay rewriting the same bytes is not a new output; changed bytes are', async () => {
    const d = mkdtempSync(join(tmpdir(), 'rc-out-')); dirs.push(d);
    writeFileSync(join(d, 'summary.csv'), 'a,b\n1,2\n');
    writeFileSync(join(d, 'fig.png'), Buffer.from([1, 2, 3]));
    const before = await snapshotDir(d);
    await new Promise((r) => setTimeout(r, 20));
    writeFileSync(join(d, 'summary.csv'), 'a,b\n1,2\n');          // replayed cell: same content
    writeFileSync(join(d, 'fig.png'), Buffer.from([1, 2, 4]));    // genuinely changed
    writeFileSync(join(d, 'new.txt'), 'x');                        // new file
    const changed = (await scanOutputDir(d)).filter((f: any) => before.get(f.name) !== f._sig).map((f) => f.name).sort();
    expect(changed).toEqual(['fig.png', 'new.txt']);
  });
});
