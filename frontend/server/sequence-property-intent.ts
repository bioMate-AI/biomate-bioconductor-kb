/** Basic properties of an explicitly supplied, unmodified linear sequence. */
export function isSimpleSequencePropertyRequest(message: string): boolean {
  const task = message.split(/\n\s*\n/)[0];
  const sequence = /\b[ACDEFGHIKLMNPQRSTVWY]{5,}\b/.exec(message)?.[0];
  if (!sequence || /^[ACGTUN]+$/.test(sequence)) return false;
  if (!/\b(protein|peptide|sequence|amino.acid)\b|蛋白|肽|氨基酸/.test(task.toLowerCase())) return false;
  if (!/\b(calculate|compute|determine|measure|report)\b|计算|求出/.test(task.toLowerCase())) return false;
  if (!/physicochemical|molecular\s+weight|isoelectric|\bpI\b|amino.acid\s+composition|分子量|等电点|氨基酸组成/i.test(task)) return false;
  // These require different science or an explicitly requested pipeline. Do not
  // silently apply linear ProtParam calculations to modified/cyclic molecules.
  return !/\b(pipeline|workflow|nextflow|fold\w*|structure|dock\w*|affinity|design\w*|generat\w*|optimi[sz]\w*|cyclic|macrocycl\w*|cycli[sz]\w*|disulfide|modified|modifications?|methylat\w*|epitope)\b|结构|折叠|设计|优化|环肽|环化|修饰|二硫键|工作流|流水线/i.test(task);
}
