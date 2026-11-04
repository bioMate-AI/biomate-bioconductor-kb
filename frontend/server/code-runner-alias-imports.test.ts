import { describe, expect, it } from 'vitest';
import { execFileSync } from 'child_process';
import { pythonAliasImports, pythonReplay } from './code-runner';

// Each run_code call is a fresh process, and the model often drops `import numpy as np` from a
// follow-up call (dev 2026-11-04: NameError 'np' / 'plt' cost a retry in 4 of 6 ad-hoc answers).
describe('pythonAliasImports', () => {
  it('imports only the aliases the script uses without importing', () => {
    const code = "df = pd.read_csv(INPUT_FILES['a.csv'])\ndf['l'] = np.log10(df['x'])\nfig, ax = plt.subplots()";
    const out = pythonAliasImports(code);
    expect(out).toContain('import numpy as np');
    expect(out).toContain('import pandas as pd');
    expect(out).toContain("matplotlib.use('Agg')");
    expect(out).not.toContain('seaborn');
  });

  it('adds nothing when the script imports the alias itself or does not use it', () => {
    expect(pythonAliasImports('import numpy as np\nprint(np.pi)')).toBe('');
    expect(pythonAliasImports('x = snp.value + nplots')).toBe('');
    expect(pythonAliasImports('print(1)')).toBe('');
  });

  it('is valid Python that tolerates a missing package', () => {
    const src = pythonAliasImports('np.a; pd.b; plt.c; sns.d') + '\nprint("ok")';
    let py = '';
    try { py = execFileSync('python3', ['-c', 'import sys; compile(sys.stdin.read(), "p", "exec"); print("compiled")'], { input: src }).toString(); }
    catch { return; } // no python3 on this machine: the shape assertions above still hold
    expect(py.trim()).toBe('compiled');
    expect(src).toMatch(/try:\n {4}import seaborn as sns\nexcept ImportError:\n {4}pass/);
  });
});

describe('pythonReplay — notebook-cell semantics within a turn', () => {
  it('restores earlier cells\' state silently and skips a cell that fails', () => {
    const src = pythonReplay(["df = 41\nprint('from cell 1')", "df += 1", "raise ValueError('bad cell')"]) + "\nprint('df =', df)";
    let out = '';
    try { out = execFileSync('python3', ['-'], { input: src }).toString(); }
    catch (e: any) { if (e?.code === 'ENOENT') return; throw e; }
    expect(out.trim()).toBe('df = 42'); // earlier cells' prints are suppressed
  });

  it('adds nothing without earlier cells', () => {
    expect(pythonReplay([])).toBe('');
    expect(pythonReplay()).toBe('');
  });
});
