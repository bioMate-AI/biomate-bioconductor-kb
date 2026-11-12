import { describe, expect, it } from "vitest"
import { stripSystemBlocks, attachedNamesFromBlocks, titleSourceText, fallbackTitle, titleHasSystemBlock } from "./chat-system-blocks"

describe("chat system blocks → user-facing text", () => {
  const msg = "Summarise the EPAR approvals by year\n[BioMate dataset: epar.jsonl (id: 1b2c-33)]\n[Uploaded datasets: epar.jsonl: dataset_id=abc]"

  it("strips every block and keeps the user's words", () => {
    expect(stripSystemBlocks(msg)).toBe("Summarise the EPAR approvals by year")
    expect(stripSystemBlocks("Q\n[Attached files: a.pdf]\n[Paper content: a.pdf]\nlong paper text…")).toBe("Q")
    expect(stripSystemBlocks("[Galaxy dataset: x]  hi")).toBe("hi")
  })

  it("strips a block truncated by an upstream slice", () => {
    expect(stripSystemBlocks("Hello [BioMate dataset: epar.jsonl (id:")).toBe("Hello")
  })

  it("names attached files for chips / attachment-only titles", () => {
    expect(attachedNamesFromBlocks(msg)).toEqual(["epar.jsonl"])
    expect(attachedNamesFromBlocks("[Attached files: a.csv, b.csv]")).toEqual(["a.csv", "b.csv"])
  })

  it("titles never contain a raw block", () => {
    expect(fallbackTitle(msg)).toBe("Summarise the EPAR approvals by year")
    expect(fallbackTitle("[BioMate dataset: epar.jsonl (id: 1)]")).toBe("epar.jsonl")
    expect(titleSourceText("[Uploaded datasets: x.csv: dataset_id=1]")).toBe("x.csv")
    expect(fallbackTitle("请分析这个数据集里的审批趋势\n[BioMate dataset: a.csv (id: 1)]")).toBe("请分析这个数据集里的审批趋势")
    for (const t of [fallbackTitle(msg), fallbackTitle("[BioMate dataset: e.jsonl (id: 1)]")]) expect(titleHasSystemBlock(t)).toBe(false)
  })

  it("detects legacy titles that still carry a block", () => {
    expect(titleHasSystemBlock("[BioMate dataset: epar.jsonl (id:")).toBe(true)
    expect(titleHasSystemBlock("EPAR approvals")).toBe(false)
  })
})

import { redactInternalRefs } from './chat-system-blocks';
describe('redactInternalRefs — never show galaxy dataset id/keyword to the user', () => {
  it('removes the JSON form the model echoes', () => {
    expect(redactInternalRefs('{"galaxy_dataset_id":"ac170aeb-1659-4c81-a7cf-b14cc2ab598e"}')).toBe('');
  });
  it('removes the key=value form, keeping the rest', () => {
    expect(redactInternalRefs('counts.csv: dataset_id=abc, galaxy_dataset_id=ac170aeb, s3_uri=x'))
      .toBe('counts.csv: dataset_id=abc'); // galaxy_dataset_id AND s3_uri both redacted
  });
  it('removes the prose colon form', () => {
    expect(redactInternalRefs('Use galaxy_dataset_id: ac170aeb for run_code'))
      .toBe('Use for run_code');
  });
  it('neutralizes a bare keyword (never the word "galaxy")', () => {
    const out = redactInternalRefs('pass the galaxy_dataset_id');
    expect(out).toBe('pass the data_id');
    expect(out.toLowerCase()).not.toContain('galaxy');
  });
  it('leaves ordinary text untouched', () => {
    expect(redactInternalRefs('Here are the DESeq2 results.')).toBe('Here are the DESeq2 results.');
    expect(redactInternalRefs('')).toBe('');
  });
});

describe('redactInternalRefs — never show internal run_code paths to the user', () => {
  it('rewrites the explicit DATA_DIR join to the clean INPUT_FILES form', () => {
    expect(redactInternalRefs("df = pd.read_csv(os.path.join(os.environ['DATA_DIR'], 'ac170aeb-1659-4c81', 'counts.csv'))"))
      .toBe("df = pd.read_csv(INPUT_FILES['counts.csv'])");
  });
  it('collapses an absolute container path to the filename', () => {
    expect(redactInternalRefs('read /work/input/ac170aeb-1659-4c81-a7cf-b14cc2ab598e/counts.csv'))
      .toBe('read counts.csv');
  });
  it('collapses a host staging path to the filename', () => {
    expect(redactInternalRefs("open('/tmp/biomate_code/sess_123/input/ac170aeb/raw.tsv')"))
      .toBe("open('raw.tsv')");
  });
  it('collapses the $DATA_DIR string form to the filename', () => {
    expect(redactInternalRefs('path=$DATA_DIR/ac170aeb/matrix.csv')).toBe('path=matrix.csv');
  });
  it('collapses a /work/output path to the filename', () => {
    expect(redactInternalRefs('wrote /work/output/results/deg_table.csv')).toBe('wrote deg_table.csv');
  });
  it('leaves ordinary user file paths untouched', () => {
    expect(redactInternalRefs('see ./data/counts.csv and /home/user/x.txt'))
      .toBe('see ./data/counts.csv and /home/user/x.txt');
  });
});

describe('redactInternalRefs — never show s3 references to the user', () => {
  it('drops the s3_uri key=value and JSON forms', () => {
    expect(redactInternalRefs('name: dataset_id=abc, s3_uri=s3://bkt/k/counts.csv'))
      .toBe('name: dataset_id=abc');
    expect(redactInternalRefs('{"s3_uri":"s3://bkt/k/x.csv"}')).toBe('');
  });
  it('collapses a bare s3:// URI to its filename', () => {
    expect(redactInternalRefs('output at s3://biomate-nextflow-work/out/run1/deg.csv'))
      .toBe('output at deg.csv');
  });
  it('neutralizes an s3 bucket with no key', () => {
    expect(redactInternalRefs('bucket is s3://biomate-nextflow-work')).toBe('bucket is a data file');
  });
});

describe("fallbackTitle — a title is a whole phrase, never a sentence cut mid-way", () => {
  it("a short first sentence is the title, whole", () => {
    expect(fallbackTitle("QC report: design_nested.tsv. Run quality control (QC) on this file and write a QC report."))
      .toBe("QC report: design_nested.tsv")
  })
  it("a long sentence is cut at a word boundary and marked as cut", () => {
    const title = fallbackTitle("design_nested.tsv: run quality control (QC) on this file and write a QC report.")
    expect(title.endsWith("…")).toBe(true)
    expect(title.length).toBeLessThanOrEqual(51)
    expect("design_nested.tsv: run quality control (QC) on this file and write a QC report.").toContain(title.slice(0, -1))
    expect(title.slice(0, -1)).not.toMatch(/\s$/)
  })
  it("a dot inside a file name does not end the sentence", () => {
    expect(fallbackTitle("Compare a.csv with b.csv")).toBe("Compare a.csv with b.csv")
  })
  it("Chinese: the first sentence (。) is the title", () => {
    expect(fallbackTitle("QC 报告：design.tsv。对此文件运行质量控制（QC），并生成 QC 报告。")).toBe("QC 报告：design.tsv")
  })
})
