/**
 * smiles-prefetch.ts — preflight PubChem lookup for chat messages.
 *
 * When a user message contains a SMILES string, hit PubChem PUG REST live
 * (the EC2 host has outbound internet) and inject the canonical compound
 * details into the prompt context before the LLM sees the message.
 *
 * This closes the chat behaviour user reported on 2026-05-19:
 *   "BioMate: I don't have outbound internet access ... However, semaglutide
 *    is a well-characterized drug..."
 *
 * Backend tools (commercial_availability.py) already query PubChem; the gap
 * was that the chat-stream path didn't call them. This file is the bridge.
 */

// SMILES heuristic: chars commonly used in SMILES strings, length 4-200,
// must contain at least one ring (digit) or bond symbol or parenthesis.
// Conservative: false negatives are fine (we just skip prefetch); false
// positives are fine (PubChem just returns nothing).
const SMILES_TOKEN = /(?:^|\s|`)([A-Za-z0-9@+\-\[\]()=#\\\/.%]{4,200})(?:$|\s|`|\.)/g;

function looksLikeSmiles(s: string): boolean {
  if (!/[A-Z]/.test(s)) return false; // SMILES has organic uppercase atoms
  if (!/[()=#\\\/0-9\[\]]/.test(s)) return false; // SMILES has bonds/rings/branches
  if (/^[A-Za-z0-9_]+$/.test(s)) return false; // pure identifiers (e.g. enzyme names)
  return true;
}

export interface PubchemHit {
  smiles: string;
  cid: number;
  iupacName?: string;
  molecularFormula?: string;
  molecularWeight?: number;
  synonyms?: string[]; // first few; canonical / brand names
}

/**
 * Look up a SMILES via PubChem PUG REST. Best-effort: returns null on any
 * error or non-match. 4-second hard timeout per request.
 */
async function lookupSmiles(smiles: string): Promise<PubchemHit | null> {
  const enc = encodeURIComponent(smiles);
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), 4000);
  try {
    const cidResp = await fetch(
      `https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/smiles/${enc}/cids/JSON`,
      { signal: controller.signal }
    );
    if (!cidResp.ok) return null;
    const cidBody: any = await cidResp.json().catch(() => null);
    const cid = cidBody?.IdentifierList?.CID?.[0];
    if (!cid || typeof cid !== "number") return null;

    const propsResp = await fetch(
      `https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/${cid}/property/IUPACName,MolecularFormula,MolecularWeight,CanonicalSMILES/JSON`,
      { signal: controller.signal }
    );
    const propsBody: any = propsResp.ok ? await propsResp.json().catch(() => null) : null;
    const p = propsBody?.PropertyTable?.Properties?.[0] || {};

    const synResp = await fetch(
      `https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/${cid}/synonyms/JSON`,
      { signal: controller.signal }
    );
    const synBody: any = synResp.ok ? await synResp.json().catch(() => null) : null;
    const synonyms: string[] = synBody?.InformationList?.Information?.[0]?.Synonym?.slice(0, 5) || [];

    return {
      smiles,
      cid,
      iupacName: p.IUPACName,
      molecularFormula: p.MolecularFormula,
      molecularWeight: typeof p.MolecularWeight === "number" ? p.MolecularWeight : (p.MolecularWeight ? Number(p.MolecularWeight) : undefined),
      synonyms,
    };
  } catch {
    return null;
  } finally {
    clearTimeout(t);
  }
}

/**
 * Extract candidate SMILES strings from a user message and resolve them
 * via PubChem. Returns up to 3 hits (per-call rate limit safety).
 */
export async function prefetchSmiles(message: string): Promise<PubchemHit[]> {
  if (!message) return [];
  const candidates = new Set<string>();
  let m: RegExpExecArray | null;
  while ((m = SMILES_TOKEN.exec(message)) !== null) {
    const tok = m[1];
    if (looksLikeSmiles(tok)) candidates.add(tok);
    if (candidates.size >= 3) break;
  }
  SMILES_TOKEN.lastIndex = 0;
  if (candidates.size === 0) return [];

  const hits = await Promise.all([...candidates].map(lookupSmiles));
  return hits.filter((h): h is PubchemHit => h !== null);
}

/**
 * Render the prefetch result as a human-readable block to prepend to the
 * user's message. Keeps Claude grounded on real compound data and stops
 * the "I lack internet" disclaimer.
 */
export function renderPrefetchContext(hits: PubchemHit[]): string {
  if (!hits.length) return "";
  const lines: string[] = [];
  lines.push("<compound_lookup_results>");
  lines.push("BioMate just queried PubChem live for the SMILES strings in this message.");
  lines.push("Use these canonical properties — do NOT claim you lack internet access.");
  lines.push("");
  for (const h of hits) {
    lines.push(`SMILES: ${h.smiles}`);
    lines.push(`  Common name(s): ${(h.synonyms && h.synonyms[0]) || "(unavailable)"}${h.synonyms && h.synonyms.length > 1 ? ` (also: ${h.synonyms.slice(1, 4).join(", ")})` : ""}`);
    lines.push(`  PubChem CID:    ${h.cid}`);
    if (h.molecularFormula) lines.push(`  Molecular formula: ${h.molecularFormula}`);
    if (h.molecularWeight) lines.push(`  Molecular weight:  ${h.molecularWeight.toFixed(2)} g/mol`);
    if (h.iupacName) lines.push(`  IUPAC name: ${h.iupacName}`);
    lines.push("");
  }
  lines.push("</compound_lookup_results>");
  return lines.join("\n");
}
