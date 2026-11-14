/**
 * Attachment → workflow-input binding.
 *
 * Each block reproduces a founder-reported failure (2026-11-11):
 *  1. "Train a potency predictor on our in-house assay data." + bace_assays.csv
 *     → the chosen workflow's required `input_smiles` stayed unbound and a
 *     "Which input_smiles?" card appeared, because the only file→param mapping
 *     was a fixed list of canonical names (samplesheet/matrix/reads/…).
 *  2. Typing "use the attached file" in that card bound the literal sentence,
 *     not the file.
 *  3. "Design nanobody candidates against this epitope." + 5 files → the panel
 *     said "parameters only — no data inputs", while an extractor had put the
 *     bare file NAME into an inline-content parameter.
 */
import { describe, it, expect } from 'vitest';
import { attachmentsNotUsed, parseAttachedFiles, attachedFilesFromMessages, bindAttachmentsToParams, bindClarificationAnswer, isFilePathParam, rebindFilenameValues, resolveAttachmentAnswer, resolveAttachedFileForValue, scoreBinding, paramAcceptsMultipleFiles, buildResolvedNfcoreInputSamplesheet, looksLikeInlineSamplesheet } from './attachment-binding';

const S3 = 's3://biomate-nextflow-work/uploads';

/** The exact block shape chat-interface.tsx appends to a message with uploads. */
function messageWith(files: Array<[string, string]>): string {
  const names = files.map(([n]) => n).join(', ');
  const refs = files
    .map(([n, id]) => `${n}: dataset_id=${id}, galaxy_dataset_id=${id.slice(0, 16)}, s3_uri=${S3}/${id}/${n}`)
    .join('; ');
  return `Train a potency predictor on our in-house assay data.\n\n[Attached files: ${names}]\n[Uploaded datasets: ${refs}]`;
}

/** Live schema of "Scaffold Hopping" (dev, /api/workflows/search 2026-11-11). */
const scaffoldHoppingParams = [
  {
    name: 'input_smiles',
    type: 'string',
    required: true,
    default: null,
    description: 'path to SMILES file (one "SMILES compound_id" per line)',
  },
  { name: 'publish_dir_mode', type: 'string', required: false, default: 'copy', description: 'Publish Dir Mode' },
  {
    name: 'reference_smiles',
    type: 'string',
    required: false,
    default: 'CC(=O)Nc1ccc(O)cc1',
    description: 'acetaminophen as default reference',
  },
  { name: 'max_candidates', type: 'integer', required: false, default: 20, description: 'maximum scaffold candidates to report' },
  { name: 'lipinski_filter', type: 'boolean', required: false, default: true, description: 'apply Lipinski rule-of-five filter' },
];

/** Live schema of "Antibody Antigen Complex" — inline-content params, no file input. */
const antibodyComplexParams = [
  { name: 'antibodies', type: 'string', required: false, default: '[{"id": "fmc63", "vh": "EVKLQESGPGLVAPSQSLSVTCTVS"}]', description: 'Workflow parameter: Antibodies' },
  { name: 'antigen_chains', type: 'string', required: false, default: '{"A": "PEELGGGGSGGGGSGGGGSQFSVLKMTT"}', description: 'Workflow parameter: Antigen Chains' },
  { name: 'target', type: 'string', required: false, default: 'demo_target', description: 'Workflow parameter: Target' },
];

describe('parseAttachedFiles', () => {
  it('reads name + dataset ids + storage uri out of the uploaded-datasets block', () => {
    const files = parseAttachedFiles(messageWith([['bace_assays.csv', '78ff4255-d078-4745-96a1-e421acf23212']]));
    expect(files).toHaveLength(1);
    expect(files[0].name).toBe('bace_assays.csv');
    expect(files[0].datasetId).toBe('78ff4255-d078-4745-96a1-e421acf23212');
    expect(files[0].s3Uri).toContain('bace_assays.csv');
  });

  it('still reports a file that only appears in [Attached files:] (upload failed → no reference)', () => {
    const files = parseAttachedFiles('do this\n\n[Attached files: broken.csv]');
    expect(files.map(f => f.name)).toEqual(['broken.csv']);
    expect(files[0].s3Uri).toBeUndefined();
  });

  it('collects a conversation\'s attachments newest-turn first, from user turns only', () => {
    const files = attachedFilesFromMessages([
      { role: 'user', content: messageWith([['old.csv', 'aaa']]) },
      { role: 'assistant', content: '[Attached files: not-a-user-upload.csv]' },
      { role: 'user', content: messageWith([['new.csv', 'bbb']]) },
    ]);
    expect(files.map(f => f.name)).toEqual(['new.csv', 'old.csv']);
  });
});

describe('isFilePathParam', () => {
  it('accepts a plain string param whose description describes a path to a file', () => {
    expect(isFilePathParam(scaffoldHoppingParams[0])).toBe(true);
  });

  it('rejects inline-content params (a literal SMILES default, a JSON default)', () => {
    expect(isFilePathParam(scaffoldHoppingParams[2])).toBe(false); // reference_smiles
    expect(isFilePathParam(antibodyComplexParams[0])).toBe(false); // antibodies
    expect(isFilePathParam(antibodyComplexParams[1])).toBe(false); // antigen_chains
    expect(isFilePathParam(antibodyComplexParams[2])).toBe(false); // target
  });

  it('accepts schema-typed file inputs regardless of wording', () => {
    expect(isFilePathParam({ name: 'input', type: 'string', format: 'file-path', description: 'Samplesheet' })).toBe(true);
    expect(isFilePathParam({ name: 'structure', type: 'file' })).toBe(true);
  });
});

describe('bindAttachmentsToParams — founder case 1 (bace_assays.csv → input_smiles)', () => {
  const files = parseAttachedFiles(messageWith([['bace_assays.csv', '78ff4255-d078-4745-96a1-e421acf23212']]));

  it('binds the attached CSV to the required SMILES file input', () => {
    const bindings = bindAttachmentsToParams(files, scaffoldHoppingParams);
    expect(bindings.map(b => b.param)).toEqual(['input_smiles']);
    expect(bindings[0].value).toBe(files[0].s3Uri);
  });

  it('never binds it to the literal reference SMILES or to settings', () => {
    const bindings = bindAttachmentsToParams(files, scaffoldHoppingParams);
    expect(bindings.some(b => ['reference_smiles', 'max_candidates', 'lipinski_filter', 'publish_dir_mode'].includes(b.param))).toBe(false);
  });

  it('binds nothing when the workflow reads no files (founder case 3)', () => {
    const nanobodyFiles = parseAttachedFiles(
      'Design nanobody candidates against this epitope.\n\n[Attached files: 6Z43.pdb, 6Z43.fasta, 1HZH.fasta, nanobody_candidates.fasta, nanobody_constraints.json]\n' +
        '[Uploaded datasets: 6Z43.pdb: dataset_id=a1, s3_uri=s3://b/a1/6Z43.pdb; 6Z43.fasta: dataset_id=a2, s3_uri=s3://b/a2/6Z43.fasta; 1HZH.fasta: dataset_id=a3, s3_uri=s3://b/a3/1HZH.fasta; nanobody_candidates.fasta: dataset_id=a4, s3_uri=s3://b/a4/nanobody_candidates.fasta; nanobody_constraints.json: dataset_id=a5, s3_uri=s3://b/a5/nanobody_constraints.json]',
    );
    expect(nanobodyFiles).toHaveLength(5);
    expect(bindAttachmentsToParams(nanobodyFiles, antibodyComplexParams)).toEqual([]);
  });
});

describe('bindAttachmentsToParams — kind safety', () => {
  const files = parseAttachedFiles(
    'x\n[Uploaded datasets: 6Z43.pdb: dataset_id=a1, s3_uri=s3://b/a1/6Z43.pdb; reads_R1.fastq.gz: dataset_id=a2, s3_uri=s3://b/a2/reads_R1.fastq.gz]',
  );

  it('does not put a structure file into a SMILES input', () => {
    expect(scoreBinding(scaffoldHoppingParams[0], files[0]).score).toBe(0);
  });

  it('matches each file to the input that asks for its kind', () => {
    const params = [
      { name: 'receptor_pdb', type: 'string', required: true, description: 'path to receptor structure file (PDB)' },
      { name: 'reads', type: 'string', required: true, description: 'path to FASTQ reads' },
    ];
    const bindings = bindAttachmentsToParams(files, params);
    expect(bindings.find(b => b.param === 'receptor_pdb')?.file.name).toBe('6Z43.pdb');
    expect(bindings.find(b => b.param === 'reads')?.file.name).toBe('reads_R1.fastq.gz');
  });

  it('leaves an optional genome reference on its default rather than hijacking it', () => {
    const fasta = parseAttachedFiles('x\n[Uploaded datasets: my_transcripts.fasta: dataset_id=z1, s3_uri=s3://b/z1/my_transcripts.fasta]');
    const params = [
      { name: 'fasta', type: 'string', format: 'file-path', required: false, default: null, description: 'Path to FASTA genome file, used as the reference' },
    ];
    expect(bindAttachmentsToParams(fasta, params)).toEqual([]);
  });

  it('binds at most one file per parameter and one parameter per file', () => {
    const two = parseAttachedFiles(
      'x\n[Uploaded datasets: a_counts.csv: dataset_id=c1, s3_uri=s3://b/c1/a_counts.csv; b_counts.csv: dataset_id=c2, s3_uri=s3://b/c2/b_counts.csv]',
    );
    const bindings = bindAttachmentsToParams(two, [
      { name: 'count_matrix', type: 'string', required: true, description: 'path to counts csv' },
    ]);
    expect(bindings).toHaveLength(1);
  });

  it('ignores a file whose upload produced no reference', () => {
    const broken = parseAttachedFiles('x\n[Attached files: broken.csv]');
    expect(bindAttachmentsToParams(broken, scaffoldHoppingParams)).toEqual([]);
  });
});

describe('rebindFilenameValues — founder case 3 (bare file name as a value)', () => {
  const files = parseAttachedFiles(
    'x\n[Uploaded datasets: nanobody_candidates.fasta: dataset_id=a4, s3_uri=s3://b/a4/nanobody_candidates.fasta; bace_assays.csv: dataset_id=a5, s3_uri=s3://b/a5/bace_assays.csv]',
  );

  it('drops a file name that an extractor put into an inline-content parameter', () => {
    const r = rebindFilenameValues({ antibodies: 'nanobody_candidates.fasta' }, files, antibodyComplexParams);
    expect(r.params).toEqual({});
    expect(r.dropped).toEqual(['antibodies']);
  });

  it('rewrites a file name on a real file parameter to its dataset reference', () => {
    const r = rebindFilenameValues({ input_smiles: 'bace_assays.csv' }, files, scaffoldHoppingParams);
    expect(r.params.input_smiles).toBe('s3://b/a5/bace_assays.csv');
    expect(r.rebound).toEqual(['input_smiles']);
  });

  it('leaves ordinary values untouched', () => {
    const r = rebindFilenameValues({ max_candidates: '20', smiles: 'CCO' }, files, scaffoldHoppingParams);
    expect(r.params).toEqual({ max_candidates: '20', smiles: 'CCO' });
    expect(r.rebound).toEqual([]);
    expect(r.dropped).toEqual([]);
  });
});

describe('structure-set pointer — Batch F (constraints.json must not bind as dataset)', () => {
  // Coldstart design-*-bio-* / pep optimise: protein_diffusion TRAIN failed with
  // ValueError: unrecognized structure-set pointer '…_constraints.json'.
  // Root cause: extractor set dataset=*_constraints.json; rebind promoted it
  // kind-blindly; attachment bind then skipped the already-bound wrong file.
  const nanobodyMsg =
    'Design nanobody candidates against this epitope.\n\n[Attached files: 6Z43.pdb, 6Z43.fasta, 1HZH.fasta, nanobody_candidates.fasta, nanobody_constraints.json]\n' +
    '[Uploaded datasets: 6Z43.pdb: dataset_id=a1, s3_uri=s3://b/a1/6Z43.pdb; 6Z43.fasta: dataset_id=a2, s3_uri=s3://b/a2/6Z43.fasta; 1HZH.fasta: dataset_id=a3, s3_uri=s3://b/a3/1HZH.fasta; nanobody_candidates.fasta: dataset_id=a4, s3_uri=s3://b/a4/nanobody_candidates.fasta; nanobody_constraints.json: dataset_id=a5, s3_uri=s3://b/a5/nanobody_constraints.json]';
  const enzymeMsg =
    'Propose enzyme variants.\n\n[Attached files: 1LYZ.pdb, 1LYZ.fasta, enzyme_candidates.fasta, enzyme_constraints.json]\n' +
    '[Uploaded datasets: 1LYZ.pdb: dataset_id=e1, s3_uri=s3://b/e1/1LYZ.pdb; 1LYZ.fasta: dataset_id=e2, s3_uri=s3://b/e2/1LYZ.fasta; enzyme_candidates.fasta: dataset_id=e3, s3_uri=s3://b/e3/enzyme_candidates.fasta; enzyme_constraints.json: dataset_id=e4, s3_uri=s3://b/e4/enzyme_constraints.json]';
  const peptideMsg =
    'Improve serum stability.\n\n[Attached files: 1BXL.pdb, 1BXL.fasta, peptide_candidates.fasta, peptide_constraints.json]\n' +
    '[Uploaded datasets: 1BXL.pdb: dataset_id=p1, s3_uri=s3://b/p1/1BXL.pdb; 1BXL.fasta: dataset_id=p2, s3_uri=s3://b/p2/1BXL.fasta; peptide_candidates.fasta: dataset_id=p3, s3_uri=s3://b/p3/peptide_candidates.fasta; peptide_constraints.json: dataset_id=p4, s3_uri=s3://b/p4/peptide_constraints.json]';

  /** Live protein_diffusion dataset label from ml_training/config.py. */
  const structureDataset = {
    name: 'dataset',
    type: 'file',
    required: true,
    label: 'Structure set (dir/manifest of PDB/mmCIF backbones, or s3://…)',
    description: 's3://…/structures/ | dir | manifest.txt | fixture:structures',
  };

  it('rebinds dataset=nanobody_constraints.json → co-attached 6Z43.pdb', () => {
    const attached = parseAttachedFiles(nanobodyMsg);
    const r = rebindFilenameValues(
      { dataset: 'nanobody_constraints.json' },
      attached,
      [structureDataset],
    );
    expect(r.params.dataset).toBe('s3://b/a1/6Z43.pdb');
    expect(r.rebound).toEqual(['dataset']);
  });

  it('rebinds dataset already pointing at the constraints s3 URI → PDB', () => {
    const attached = parseAttachedFiles(nanobodyMsg);
    const r = rebindFilenameValues(
      { dataset: 's3://b/a5/nanobody_constraints.json' },
      attached,
      [structureDataset],
    );
    expect(r.params.dataset).toBe('s3://b/a1/6Z43.pdb');
  });

  it('resolves a staged basename …_enzyme_constraints.json back to the attachment', () => {
    const attached = parseAttachedFiles(enzymeMsg);
    expect(resolveAttachedFileForValue('1cadc4aea8_enzyme_constraints.json', attached)?.name)
      .toBe('enzyme_constraints.json');
  });

  it('overwrites a wrong-kind pre-bound dataset with the PDB in bindAttachmentsToParams', () => {
    const attached = parseAttachedFiles(peptideMsg);
    const params = [{
      ...structureDataset,
      value: 's3://b/p4/peptide_constraints.json',
    }];
    const bindings = bindAttachmentsToParams(attached, params);
    expect(bindings).toHaveLength(1);
    expect(bindings[0].file.name).toBe('1BXL.pdb');
    expect(bindings[0].value).toBe('s3://b/p1/1BXL.pdb');
  });

  it('binds 1LYZ.pdb (not enzyme_constraints.json) when dataset is empty', () => {
    const attached = parseAttachedFiles(enzymeMsg);
    const bindings = bindAttachmentsToParams(attached, [structureDataset]);
    expect(bindings.map((b) => b.file.name)).toEqual(['1LYZ.pdb']);
  });
});

describe('multi-file inputs — hospital multi-omics bundle (dev d303eca6)', () => {
  // "Integrate a multi-omics cohort (RNA, protein, methylation) with SNF" attaches
  // the three modality tables plus evaluation truth and bundle documentation.
  const bundle = [
    'rna.csv', 'protein.csv', 'methyl.csv',
    'ground_truth.csv', 'true_drivers.csv', 'README.md', 'provenance.json',
  ];
  const files = parseAttachedFiles(
    'Integrate the attached multi-omics cohort with SNF.\n\n' +
      `[Attached files: ${bundle.join(', ')}]\n[Uploaded datasets: ` +
      bundle.map((n, i) => `${n}: dataset_id=d${i}, s3_uri=s3://b/d${i}/${n}`).join('; ') +
      ']',
  );
  /** MOFA2's single multi-modality input, as the chat card describes it. */
  const omics = [{
    name: 'omics', type: 'file', required: true, default: null,
    description: 'One features×samples CSV per modality (RNA, proteomics)',
  }];

  it('binds all three modality tables to the one multi-file parameter', () => {
    const bindings = bindAttachmentsToParams(files, omics);
    expect(bindings).toHaveLength(1);
    expect(bindings[0].files.map(f => f.name)).toEqual(['rna.csv', 'protein.csv', 'methyl.csv']);
    expect(bindings[0].value).toBe('s3://b/d0/rna.csv,s3://b/d1/protein.csv,s3://b/d2/methyl.csv');
  });

  it('never binds evaluation truth as a feature layer, or bundle documentation', () => {
    const bound = bindAttachmentsToParams(files, omics)[0].files.map(f => f.name);
    expect(bound).not.toContain('ground_truth.csv');
    expect(bound).not.toContain('true_drivers.csv');
    expect(bound).not.toContain('README.md');
    expect(bound).not.toContain('provenance.json');
  });

  it('still binds the truth file to a parameter that explicitly asks for it', () => {
    const truthParam = [{ name: 'ground_truth', type: 'file', required: true, description: 'known cluster labels for evaluation' }];
    const b = bindAttachmentsToParams(files, truthParam);
    expect(b[0]?.file.name).toBe('ground_truth.csv');
  });

  it('keeps one file per parameter for a single-valued input', () => {
    const single = [{ name: 'expression_matrix', type: 'file', required: true, description: 'features×samples CSV' }];
    expect(bindAttachmentsToParams(files, single)[0].files).toHaveLength(1);
  });

  it('binds a schema-typed file input that carries no descriptive text', () => {
    const thin = [{ name: 'omics', type: 'file', description: 'Omics' }];
    expect(bindAttachmentsToParams(files, thin)[0].files.map(f => f.name))
      .toEqual(['rna.csv', 'protein.csv', 'methyl.csv']);
  });

  it('prefers the modality table whose name matches the parameter', () => {
    const citefuse = [
      { name: 'RNA_counts', type: 'file', description: 'Rna Counts' },
      { name: 'ADT_counts', type: 'file', description: 'Adt Counts' },
    ];
    const b = bindAttachmentsToParams(files, citefuse);
    expect(b.find(x => x.param === 'RNA_counts')?.file.name).toBe('rna.csv');
  });
});

describe('attachmentsNotUsed — the reply must not claim data it does not read', () => {
  const report = {
    attached: ['6Z43.pdb', 'nanobody_candidates.fasta'],
    bound: [] as Array<{ param: string; file: string }>,
    unbound: ['6Z43.pdb', 'nanobody_candidates.fasta'],
  };

  it('names the files when a runnable workflow binds none of them and waits for nothing', () => {
    expect(attachmentsNotUsed(report, { runnableWorkflow: true, unboundRequiredInputs: 0 }))
      .toEqual(['6Z43.pdb', 'nanobody_candidates.fasta']);
  });

  it('says nothing when the workflow is merely waiting for its data input', () => {
    expect(attachmentsNotUsed(report, { runnableWorkflow: true, unboundRequiredInputs: 1 })).toEqual([]);
  });

  it('says nothing when a file was bound, or when there is no runnable workflow', () => {
    const bound = { ...report, bound: [{ param: 'input_smiles', file: 'bace_assays.csv' }] };
    expect(attachmentsNotUsed(bound, { runnableWorkflow: true, unboundRequiredInputs: 0 })).toEqual([]);
    expect(attachmentsNotUsed(report, { runnableWorkflow: false, unboundRequiredInputs: 0 })).toEqual([]);
    expect(attachmentsNotUsed(undefined, { runnableWorkflow: true, unboundRequiredInputs: 0 })).toEqual([]);
  });
});

describe('clarification answers that refer to an attachment — founder case 2', () => {
  const files = parseAttachedFiles(messageWith([['bace_assays.csv', '78ff4255-d078-4745-96a1-e421acf23212']]));
  const ref = files[0].s3Uri!;

  it('"use the attached file" binds the file, not the sentence', () => {
    const r = bindClarificationAnswer('use the attached file', files, scaffoldHoppingParams[0]);
    expect(r.bound).toBe(true);
    expect(r.value).toBe(ref);
  });

  it('accepts the Chinese phrasing', () => {
    expect(bindClarificationAnswer('用附件', files, scaffoldHoppingParams[0]).value).toBe(ref);
    expect(bindClarificationAnswer('使用我上传的文件', files, scaffoldHoppingParams[0]).value).toBe(ref);
  });

  it('accepts the file name, with or without its extension', () => {
    expect(bindClarificationAnswer('bace_assays.csv', files, scaffoldHoppingParams[0]).value).toBe(ref);
    expect(bindClarificationAnswer('bace_assays', files, scaffoldHoppingParams[0]).value).toBe(ref);
  });

  it('passes a real value through unchanged', () => {
    const r = bindClarificationAnswer('CC(=O)Nc1ccc(O)cc1', files, scaffoldHoppingParams[0]);
    expect(r.bound).toBe(false);
    expect(r.value).toBe('CC(=O)Nc1ccc(O)cc1');
  });

  it('picks the file that fits the parameter when several are attached', () => {
    const many = parseAttachedFiles(
      'x\n[Uploaded datasets: 6Z43.pdb: dataset_id=a1, s3_uri=s3://b/a1/6Z43.pdb; compounds.csv: dataset_id=a2, s3_uri=s3://b/a2/compounds.csv]',
    );
    const f = resolveAttachmentAnswer('use the attached file', many, scaffoldHoppingParams[0]);
    expect(f?.name).toBe('compounds.csv');
  });

  it('does not guess when several attachments fit equally and no parameter is known', () => {
    const many = parseAttachedFiles(
      'x\n[Uploaded datasets: a.csv: dataset_id=a1, s3_uri=s3://b/a1/a.csv; b.csv: dataset_id=a2, s3_uri=s3://b/a2/b.csv]',
    );
    expect(resolveAttachmentAnswer('use the attached file', many)).toBeNull();
  });
});

describe('file[] multi-file params (SNF/MOFA2 omics) bind every attachment', () => {
  const omics = { name: 'omics', type: 'file[]', required: true, description: 'One features×samples CSV per modality (RNA, proteomics).' } as any;
  const f = (name: string, id: string) => ({ name, datasetId: id, s3Uri: `s3://b/${id}/${name}` } as any);
  it('isFilePathParam recognises file[]', () => {
    expect(isFilePathParam(omics)).toBe(true);
    expect(paramAcceptsMultipleFiles(omics)).toBe(true);
  });
  it('binds all three modality CSVs to omics as a comma-separated list', () => {
    const files = [f('rna.csv', 'a'), f('protein.csv', 'b'), f('methyl.csv', 'c')];
    const out = bindAttachmentsToParams(files, [omics]);
    expect(out.length).toBe(1);
    expect(out[0].param).toBe('omics');
    expect(out[0].value.split(',').length).toBe(3);
    expect(out[0].files.map((x: any) => x.name)).toEqual(['rna.csv', 'protein.csv', 'methyl.csv']);
  });
});

describe('multi-file param pre-bound to one file is topped up with the rest', () => {
  const f = (name: string) => ({ name, datasetId: name, s3Uri: `s3://b/${name}` } as any);
  it('omics already set to rna.csv gains protein.csv + methyl.csv', () => {
    const omics = { name: 'omics', type: 'file[]', required: true, value: 's3://b/rna.csv', autoFilled: true, description: 'One features×samples CSV per modality.' } as any;
    const out = bindAttachmentsToParams([f('rna.csv'), f('protein.csv'), f('methyl.csv')], [omics]);
    expect(out.length).toBe(1);
    expect(out[0].value.split(',').length).toBe(3);
  });
  it('a single-value param that is already bound is left alone', () => {
    const inp = { name: 'input_smiles', type: 'file', required: true, value: 's3://b/a.smi', autoFilled: true } as any;
    const out = bindAttachmentsToParams([f('a.smi'), f('b.smi')], [inp]);
    expect(out.length).toBe(0);
  });
});

describe('buildResolvedNfcoreInputSamplesheet', () => {
  const f = (name: string) => ({
    name,
    datasetId: name,
    s3Uri: `s3://biomate-nextflow-work/uploads/${name}`,
  });

  it('builds a sarek tumor/normal sheet with resolvable FASTQ URIs', () => {
    const sheet = buildResolvedNfcoreInputSamplesheet('nf-core/sarek', [
      f('normal_R1.fastq.gz'),
      f('normal_R2.fastq.gz'),
      f('tumor_R1.fastq.gz'),
      f('tumor_R2.fastq.gz'),
      f('sequencing_samples.csv'),
      f('reference_grch37.fasta'),
    ]);
    expect(sheet).not.toBeNull();
    expect(looksLikeInlineSamplesheet(sheet!.csv)).toBe(true);
    expect(sheet!.csv).toContain('patient,sample,sex,status,lane,fastq_1,fastq_2');
    expect(sheet!.csv).toMatch(/demo,normal,NA,0,1,s3:\/\/.*normal_R1/);
    expect(sheet!.csv).toMatch(/demo,tumor,NA,1,1,s3:\/\/.*tumor_R1/);
    expect(sheet!.csv).not.toMatch(/(?<!\/)normal_R1\.fastq\.gz,/); // no bare basename cells
  });

  it('builds a proteinfold id,fasta sheet from 1BXL.fasta', () => {
    const sheet = buildResolvedNfcoreInputSamplesheet('nf-core/proteinfold', [
      f('1BXL.pdb'),
      f('1BXL.fasta'),
      f('peptide_candidates.fasta'),
      f('proteinfold_samplesheet.csv'),
    ]);
    expect(sheet).not.toBeNull();
    expect(sheet!.csv.split('\n')[0]).toBe('id,fasta');
    expect(sheet!.csv).toContain('s3://biomate-nextflow-work/uploads/1BXL.fasta');
  });

  it('returns null when required FASTQs are missing', () => {
    expect(buildResolvedNfcoreInputSamplesheet('nf-core/sarek', [f('sequencing_samples.csv')])).toBeNull();
  });
});

describe('looksLikeInlineSamplesheet', () => {
  it('detects sarek / proteinfold / rnaseq headers', () => {
    expect(looksLikeInlineSamplesheet('patient,sample,sex,status,lane,fastq_1,fastq_2\n')).toBe(true);
    expect(looksLikeInlineSamplesheet('id,fasta\nx,s3://b/a.fa\n')).toBe(true);
    expect(looksLikeInlineSamplesheet('sample,fastq_1,fastq_2\n')).toBe(true);
    expect(looksLikeInlineSamplesheet('s3://bucket/sheet.csv')).toBe(false);
  });
});
