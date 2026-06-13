#!/usr/bin/env node
// Schema-grounded extraction probe.
// Parses params from each tier-0 .nf and asks Claude Haiku to extract canonical-keyed values.
import 'dotenv/config';
import fs from 'node:fs';
import path from 'node:path';

const NF_ROOT = '/home/yzhang/biomate/backend/nf-core-workflows/modules/biomate-ai-tools';

const DEMOS = [
  { wf: 'bispecific_format_triage',  query: 'Design a PD-1 x VEGF bispecific in CrossMab format for NSCLC',                                  expect: { target_a: /pd-?1/i, target_b: /vegf/i, indication: /nsclc/i } },
  { wf: 'in_vivo_cart_codesign',     query: 'Co-design an in-vivo CD19 CAR-T for DLBCL with LNP delivery to T cells, transient persistence', expect: { car_target: /cd19/i, indication: /dlbcl/i, delivery_cell: /t.?cell/i, persistence: /transient/i } },
  { wf: 'in_vivo_base_edit_design',  query: 'Design an in-vivo base-edit knockout of PCSK9 for hypercholesterolemia',                        expect: { target_gene: /pcsk9/i, edit_goal: /loss.?of.?function|knockout/i, indication: /hyperchol/i } },
  { wf: 'glp1_modality_bakeoff',     query: 'Compare GLP-1 modalities for MASH — peptide vs mRNA vs gene therapy',                           expect: { indication: /mash|nash/i } },
  { wf: 'modality_triage',           query: 'Triage modalities for a BCMA oncology target — try all options',                                expect: { target_gene: /bcma/i, indication: /onco|cancer/i } },
];

// Parse params.X = 'default'  // optional comment-with-enum
function parseParams(nfText) {
  const out = [];
  const re = /^params\.(\w+)\s*=\s*(['"])([^'"]*)\2\s*(?:\/\/\s*(.*))?$/gm;
  let m;
  while ((m = re.exec(nfText)) !== null) {
    const [, name, , def, comment] = m;
    if (name === 'outdir') continue;
    const param = { name, default: def };
    if (comment) {
      const trimmed = comment.trim();
      if (trimmed.includes('|')) {
        // enum
        param.enum = trimmed.split('|').map(s => s.trim()).filter(Boolean);
      } else if (trimmed.toLowerCase().startsWith('alias for')) {
        param.alias_of = trimmed.replace(/^alias for\s+/i, '').trim();
      } else {
        param.note = trimmed;
      }
    }
    out.push(param);
  }
  return out;
}

function buildPrompt(workflowName, params, userQuery) {
  const lines = params.map(p => {
    let s = `- ${p.name}`;
    if (p.enum) s += ` (allowed: ${p.enum.join(' | ')})`;
    else if (p.alias_of) s += ` (alias of ${p.alias_of} — prefer the primary key)`;
    if (p.note) s += ` — ${p.note}`;
    return s;
  }).join('\n');
  return `You extract scientific parameters for the workflow "${workflowName}" from a user's request.

Extract values for ONLY these parameters (use the EXACT key names below; omit any parameter the user did not mention or imply):

${lines}

Rules:
- Use the user's literal words when possible. Normalize obvious synonyms ("T cells" → "T_cell") if the parameter has an allowed values list.
- If the user mentions multiple values for a list-typed parameter (e.g. "peptide vs mRNA vs gene therapy"), join with commas.
- Do NOT invent keys not in the list above.
- If a parameter has an "alias of X" note, store the value under X, not the alias.
- Return ONLY a JSON object. No prose.

User request: "${userQuery}"

JSON:`;
}

async function callClaude(prompt) {
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 400,
      messages: [{ role: 'user', content: prompt }],
    }),
  });
  if (!r.ok) throw new Error(`Claude API ${r.status}: ${await r.text()}`);
  const j = await r.json();
  const text = j.content?.[0]?.text || '';
  // Strip ``` fences if any.
  const m = text.match(/\{[\s\S]*\}/);
  return m ? JSON.parse(m[0]) : { _raw: text };
}

function check(extracted, expect) {
  const results = {};
  let pass = 0, total = 0;
  for (const [k, re] of Object.entries(expect)) {
    total++;
    const v = extracted[k];
    const ok = v !== undefined && re.test(String(v));
    results[k] = { value: v, expect: re.toString(), pass: ok };
    if (ok) pass++;
  }
  return { results, pass, total };
}

(async () => {
  const summary = [];
  for (const demo of DEMOS) {
    const nfPath = path.join(NF_ROOT, demo.wf, 'main.nf');
    const params = parseParams(fs.readFileSync(nfPath, 'utf8'));
    const prompt = buildPrompt(demo.wf, params, demo.query);
    let extracted;
    try { extracted = await callClaude(prompt); }
    catch (e) { extracted = { _error: e.message }; }
    const { results, pass, total } = check(extracted, demo.expect);
    summary.push({ wf: demo.wf, pass, total, extracted, results });
    console.log(`\n=== ${demo.wf} (${pass}/${total}) ===`);
    console.log('Schema keys:', params.map(p => p.name).join(', '));
    console.log('Query:', demo.query);
    console.log('Extracted:', JSON.stringify(extracted));
    for (const [k, r] of Object.entries(results)) {
      console.log(`  ${r.pass ? '✓' : '✗'} ${k}: got=${JSON.stringify(r.value)} expect=${r.expect}`);
    }
  }
  const totalPass = summary.reduce((a, s) => a + s.pass, 0);
  const totalTotal = summary.reduce((a, s) => a + s.total, 0);
  console.log(`\n=== TOTAL: ${totalPass}/${totalTotal} keys extracted correctly ===`);
})();
