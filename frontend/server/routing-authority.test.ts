/**
 * The intent classifier is the single authority for workflow-vs-not
 * (docs/20261110_ROUTING_CLASSIFIER_AUTHORITY.md). These tests pin that no post-classifier step
 * flips needsWorkflowGeneration except the explicit-prohibition and BOIN-prerequisite gates.
 */
import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  applyRetrievalHints, applyUserConstraintGate, boinDoseLevelsMissing, isDmtaLoopQuery, MODELS_DMTA_HREF, parseUserConstraint,
  reconcileExecutionMode, type RoutingIntent,
} from './routing-authority';
import { GalaxyAssistant } from './galaxy-assistant';
import { ROUTING_EXAMPLE_GROUPS, routingExamplesPrompt } from './routing-examples';

const mk = (nwg: boolean, extra: Partial<RoutingIntent> = {}): RoutingIntent => ({
  type: nwg ? 'workflow_generation' : 'research_question', subQuery: '', actions: { needsWorkflowGeneration: nwg }, ...extra,
});

// Messages that used to trip a regex override (each flipped the classifier's decision).
const FORMER_OVERRIDE_TRIGGERS = [
  'Show target evidence for CHRNA1 in MG',
  'Estimate recruitment feasibility for an MG phase 3 trial',
  'Run pathway enrichment on complement genes C3, C5, CFB',
  'pull GWAS hits near TNFSF13B and eQTL colocalization',
  'integrate RNA-seq with Olink proteomics',
  'macrophage M1 M2 polarization in CIDP nerve',
  'DESeq2 on the airway dataset',
  'AutoDock Vina site-directed docking into 1M17',
  'run nf-core/epitopeprediction with mhcnuggets',
  'fpocket druggability on 3HTB',
  'hERG for SMILES: CC(=O)Oc1ccccc1C(=O)O',
  'HP:0001250 HP:0001263 ENSG00000141510 ENSG00000012048 which is causal',
  'also add the other two files',
  'use run_code to compute the mean of [1,2,3]',
  'train a classifier model on my data',
  '先做第一步', '你可以直接编程统计吗 不用工作流', '第2-5步，并提供结果文件下载链接',
];

describe('retrieval hints never change the workflow decision', () => {
  for (const m of FORMER_OVERRIDE_TRIGGERS) {
    for (const nwg of [true, false]) {
      it(`${nwg ? 'workflow' : 'no-workflow'} stays as classified: ${m}`, () => {
        const intent = mk(nwg, { subQuery: m });
        const decomp = {};
        applyRetrievalHints(intent, decomp, m);
        expect(intent.actions.needsWorkflowGeneration).toBe(nwg);
      });
    }
  }
  it('steers search for an enrichment workflow the classifier chose', () => {
    const intent = mk(true, { subQuery: 'I have your counts matrix' });
    const decomp: any = { keyTerms: ['nf-core/differentialabundance'] };
    const r = applyRetrievalHints(intent, decomp, '对这些基因做KEGG富集分析');
    expect(r.pathwayEnrichment).toBe(true);
    expect(decomp.keyTerms).toContain('clusterprofiler');
    expect(decomp.keyTerms).not.toContain('nf-core/differentialabundance');
    expect(decomp.penalizedDomains).toContain('transcriptomics');
    expect(intent.subQuery).toBe('对这些基因做KEGG富集分析');
  });
  it('adds no hints to a non-workflow turn', () => {
    const decomp: any = {};
    expect(applyRetrievalHints(mk(false), decomp, 'GSEA vs ORA?').pathwayEnrichment).toBe(false);
    expect(decomp.keyTerms).toBeUndefined();
  });
});

describe('reconcileExecutionMode — the classifier\'s execution mode wins over its own flag', () => {
  it('direct_compute with data in the conversation ⇒ no workflow card (run_code stays enabled)', () => {
    const i = mk(true, { execution: 'direct_compute' });
    reconcileExecutionMode(i, true);
    expect(i.actions.needsWorkflowGeneration).toBe(false);
    expect(i.actions.needsLLMReasoning).toBe(true);
  });
  it('direct_compute with NO data anywhere contradicts its own contract ⇒ the workflow card stays (EBV, dev 2026-11-11)', () => {
    const i = mk(true, { execution: 'direct_compute' });
    reconcileExecutionMode(i, false);
    expect(i.actions.needsWorkflowGeneration).toBe(true);
  });
  it('pipeline / null leave the flag alone', () => {
    for (const execution of ['pipeline', null] as const) {
      for (const hasData of [true, false]) {
        const a = mk(true, { execution }); reconcileExecutionMode(a, hasData); expect(a.actions.needsWorkflowGeneration).toBe(true);
        const b = mk(false, { execution }); reconcileExecutionMode(b, hasData); expect(b.actions.needsWorkflowGeneration).toBe(false);
      }
    }
  });
});

describe('user-constraint gate (kept: explicit user control, consumes classifier user_constraint)', () => {
  it('classifier user_constraint=no_workflow suppresses generation in any language', () => {
    const i = mk(true, { userConstraint: 'no_workflow' });
    expect(applyUserConstraintGate(i, '这个就别弄流程了')).toBe('suppressed');
    expect(i.actions.needsWorkflowGeneration).toBe(false);
    expect(i.type).toBe('research_question');
  });
  it('no_workflow + direct_compute keeps the run_code path (not research)', () => {
    const i = mk(true, { userConstraint: 'no_workflow', execution: 'direct_compute' });
    applyUserConstraintGate(i, '不用工作流，直接算');
    expect(i.actions.needsWorkflowGeneration).toBe(false);
    expect(i.type).toBe('workflow_generation');
  });
  it('regex safety net still honours an English interpretation-only prohibition', () => {
    const i = mk(true);
    applyUserConstraintGate(i, 'Interpret these PK values but do not run any simulation');
    expect(i.actions.needsWorkflowGeneration).toBe(false);
    expect(i.type).toBe('data_interpretation');
  });
  it('no_launch keeps the draft card', () => {
    const i = mk(true, { userConstraint: 'no_launch' });
    expect(applyUserConstraintGate(i, 'draft it, launch later')).toBe('draft');
    expect(i.actions.needsWorkflowGeneration).toBe(true);
  });
  it('never turns a non-workflow decision into a workflow', () => {
    const i = mk(false, { userConstraint: 'no_launch' });
    expect(applyUserConstraintGate(i, 'x')).toBe('none');
    expect(i.actions.needsWorkflowGeneration).toBe(false);
  });
  it('parseUserConstraint accepts only the closed vocabulary', () => {
    expect(parseUserConstraint('no_workflow')).toBe('no_workflow');
    expect(parseUserConstraint('no_launch')).toBe('no_launch');
    expect(parseUserConstraint('maybe')).toBeNull();
  });
});

describe('BOIN prerequisite gate', () => {
  it('asks for dose levels when missing (EN, ZH, or via the classifier subQuery)', () => {
    expect(boinDoseLevelsMissing(mk(true), 'Design a BOIN trial for my compound')).toBe(true);
    expect(boinDoseLevelsMissing(mk(true), '设计一个剂量递增试验')).toBe(true);
    expect(boinDoseLevelsMissing(mk(true, { subQuery: 'BOIN phase I dose escalation design' }), '帮我设计一期试验')).toBe(true);
  });
  it('does not ask when dose levels are given', () => {
    expect(boinDoseLevelsMissing(mk(true), 'BOIN with dose levels [10, 30, 60]')).toBe(false);
    expect(boinDoseLevelsMissing(mk(true), '设计BOIN试验，剂量水平 [10, 30, 60] mg')).toBe(false);
    expect(boinDoseLevelsMissing(mk(true, { inlineParameters: { dose_levels: '10,20,40' } }), 'BOIN design')).toBe(false);
  });
  it('only applies to a workflow decision', () => {
    expect(boinDoseLevelsMissing(mk(false), 'What is BOIN?')).toBe(false);
  });
});

describe('DMTA / Models Optimise loop detection', () => {
  it('matches cold-start Optimise seeds', () => {
    expect(isDmtaLoopQuery('Run the design–make–test loop on this series under a 96-assay budget.')).toBe(true);
    expect(isDmtaLoopQuery('Propose the next round and refit on the results.')).toBe(true);
  });
  it('does not treat generative lead design as DMTA', () => {
    expect(isDmtaLoopQuery('Generate 500 candidates for this target with drug-like properties.')).toBe(false);
    expect(isDmtaLoopQuery('Scaffold-hop away from this series but keep the binding pharmacophore.')).toBe(false);
  });
  it('deep-links to Models Molecular Rounds, not CRO Library', () => {
    expect(MODELS_DMTA_HREF).toBe('/models?tab=molecular');
    expect(MODELS_DMTA_HREF).not.toContain('drug-discovery-cro');
  });
});

describe('parseIntentResult honours the classifier (mustGenerateWorkflow removed)', () => {
  const parse = (r: any) => (GalaxyAssistant.prototype as any).parseIntentResult.call({}, r, 'm');
  it('workflow_generation + execution=direct_compute ⇒ needsWorkflowGeneration=false', () => {
    const d = parse({ type: 'workflow_generation', execution: 'direct_compute', actions: { needsWorkflowGeneration: true } });
    expect(d.primaryIntent.actions.needsWorkflowGeneration).toBe(false);
  });
  it('workflow_generation + needsWorkflowGeneration=false (run_code branch) is kept, not forced true', () => {
    const d = parse({ type: 'workflow_generation', actions: { needsWorkflowGeneration: false } });
    expect(d.primaryIntent.actions.needsWorkflowGeneration).toBe(false);
  });
  it('a pipeline decision is kept', () => {
    const d = parse({ type: 'workflow_generation', execution: 'pipeline', actions: { needsWorkflowGeneration: true } });
    expect(d.primaryIntent.actions.needsWorkflowGeneration).toBe(true);
  });
  it('parses user_constraint on single and multi-intent replies', () => {
    expect(parse({ type: 'data_interpretation', user_constraint: 'no_workflow' }).primaryIntent.userConstraint).toBe('no_workflow');
    const m = parse({ user_constraint: 'no_launch', intents: [{ id: 'a', type: 'workflow_generation' }, { id: 'b', type: 'workflow_generation' }] });
    expect(m.intents.every((i: any) => i.userConstraint === 'no_launch')).toBe(true);
  });
  it('multi-intent direct_compute branch carries no workflow', () => {
    const m = parse({ intents: [{ id: 'a', type: 'workflow_generation', execution: 'direct_compute', actions: { needsWorkflowGeneration: true } }, { id: 'b', type: 'research_question' }] });
    expect(m.intents[0].actions.needsWorkflowGeneration).toBe(false);
  });
});

describe('_applyPostClassifierRouting flips nothing on former override triggers', () => {
  const ga = GalaxyAssistant.prototype as any;
  for (const m of FORMER_OVERRIDE_TRIGGERS) {
    for (const nwg of [true, false]) {
      it(`${nwg}: ${m}`, () => {
        const intent: any = { type: nwg ? 'workflow_generation' : 'research_question', subQuery: m, actions: { needsWorkflowGeneration: nwg } };
        ga._applyPostClassifierRouting.call(ga, intent, {}, m, {});
        expect(intent.actions.needsWorkflowGeneration).toBe(nwg);
      });
    }
  }
});

describe('classifier prompt examples (founder requirement: ≥3 per removed override, zh+en, boundary)', () => {
  const zh = (t: string) => /[一-鿿]/.test(t);
  for (const g of ROUTING_EXAMPLE_GROUPS) {
    it(`${g.key}: ≥3 examples, mixes zh and en, states type/execution/nwg`, () => {
      expect(g.examples.length).toBeGreaterThanOrEqual(3);
      expect(g.examples.some(e => zh(e.text))).toBe(true);
      expect(g.examples.some(e => !zh(e.text))).toBe(true);
      for (const e of g.examples) expect(typeof e.nwg).toBe('boolean');
      // execution ⇒ flag consistency
      for (const e of g.examples) if (e.execution === 'direct_compute') expect(e.nwg).toBe(false);
    });
  }
  it('flag-gated ml_training examples only appear when the flag is on', () => {
    expect(routingExamplesPrompt({})).not.toContain('XGBoost');
    expect(routingExamplesPrompt({ ML_TRAINING_ROUTING: '1' })).toContain('XGBoost');
  });
  it('the held-out replay set never reuses a prompt example wording', () => {
    const here = path.dirname(fileURLToPath(import.meta.url));
    const cases = JSON.parse(readFileSync(path.join(here, '../../scripts/routing_replay/cases.json'), 'utf8')).cases as any[];
    const norm = (t: string) => t.replace(/["“”]/g, '').replace(/\s+/g, ' ').trim().toLowerCase();
    const exampleTexts = ROUTING_EXAMPLE_GROUPS.flatMap(g => g.examples.map(e => norm(e.text.match(/"([^"]+)"/)?.[1] ?? e.text)));
    for (const c of cases) for (const e of exampleTexts) expect(norm(c.text).includes(e) || e.includes(norm(c.text)), `${c.id} reuses "${e}"`).toBe(false);
  });
});
