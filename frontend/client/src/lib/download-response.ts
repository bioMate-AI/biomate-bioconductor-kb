/**
 * Download assistant response as .txt, .md, or .docx.
 * LLM produces the content; this module handles format conversion — no extra API calls.
 */

function triggerDownload(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

function slugify(text: string): string {
  return (
    text.slice(0, 40).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') ||
    'biomate-response'
  );
}

export function downloadAsTxt(content: string, title?: string) {
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
  triggerDownload(blob, `${slugify(title || content)}.txt`);
}

export function downloadAsMd(content: string, title?: string) {
  const blob = new Blob([content], { type: 'text/markdown;charset=utf-8' });
  triggerDownload(blob, `${slugify(title || content)}.md`);
}

/**
 * Convert markdown text → .docx using the `docx` npm library (runs in browser).
 * Handles: h1/h2/h3, **bold**, *italic*, bullet lists, numbered lists, plain paragraphs.
 */
export async function downloadAsDocx(content: string, title?: string) {
  const { Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType } = await import('docx');

  /** Split a line into TextRun[] respecting **bold** and *italic* markers */
  function inlineRuns(text: string): InstanceType<typeof TextRun>[] {
    const runs: InstanceType<typeof TextRun>[] = [];
    const re = /(\*\*\*(.+?)\*\*\*|\*\*(.+?)\*\*|\*(.+?)\*|_(.+?)_)/g;
    let last = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(text)) !== null) {
      if (m.index > last) runs.push(new TextRun(text.slice(last, m.index)));
      if (m[2]) runs.push(new TextRun({ text: m[2], bold: true, italics: true }));
      else if (m[3]) runs.push(new TextRun({ text: m[3], bold: true }));
      else if (m[4] || m[5]) runs.push(new TextRun({ text: (m[4] || m[5]), italics: true }));
      last = m.index + m[0].length;
    }
    if (last < text.length) runs.push(new TextRun(text.slice(last)));
    return runs.length ? runs : [new TextRun(text)];
  }

  const children: InstanceType<typeof Paragraph>[] = [];

  for (const line of content.split('\n')) {
    if (line.startsWith('### '))
      children.push(new Paragraph({ text: line.slice(4).trim(), heading: HeadingLevel.HEADING_3 }));
    else if (line.startsWith('## '))
      children.push(new Paragraph({ text: line.slice(3).trim(), heading: HeadingLevel.HEADING_2 }));
    else if (line.startsWith('# '))
      children.push(new Paragraph({ text: line.slice(2).trim(), heading: HeadingLevel.HEADING_1 }));
    else if (/^[-*•]\s+/.test(line))
      children.push(new Paragraph({ children: inlineRuns(line.replace(/^[-*•]\s+/, '')), bullet: { level: 0 } }));
    else if (/^\d+\.\s+/.test(line))
      children.push(new Paragraph({
        children: inlineRuns(line.replace(/^\d+\.\s+/, '')),
        numbering: { reference: 'default-numbering', level: 0 },
      }));
    else if (line.trim() === '')
      children.push(new Paragraph({ text: '' }));
    else
      children.push(new Paragraph({ children: inlineRuns(line) }));
  }

  const doc = new Document({
    numbering: {
      config: [{
        reference: 'default-numbering',
        levels: [{ level: 0, format: 'decimal', text: '%1.', alignment: AlignmentType.LEFT }],
      }],
    },
    sections: [{ children }],
  });

  const buffer = await Packer.toBuffer(doc);
  const blob = new Blob([buffer], {
    type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  });
  triggerDownload(blob, `${slugify(title || content)}.docx`);
}
