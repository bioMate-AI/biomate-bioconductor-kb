/**
 * Catalog search terms for a user's query. The workflow catalog is indexed in English, so a Chinese
 * (or Japanese / Korean) query matched nothing in the Workflows library (founder 2026-11-12: "using
 * Chinese for search returns nothing"). A CJK query is turned into concise English search terms by
 * one cached LLM call; tool, gene and accession names stay verbatim. Any failure falls back to the
 * original text (never worse than before). Not a keyword dictionary.
 */
import { callGeminiFlash } from './gemini-flash';

const CJK = /[぀-ヿ㐀-鿿가-힯]/;
const cache = new Map<string, string>();

const SYSTEM = `You turn a bioinformatics / drug-discovery workflow search query into concise ENGLISH
catalog search terms. Keep tool, model, gene, protein, file-format and accession names exactly as
written (e.g. DESeq2, ADMET, SMILES, scRNA-seq, GSE12345). Translate everything else by meaning.
Return only the search terms on one line — no quotes, no explanation.`;

export async function searchQueryForCatalog(
  query: string,
  llm: typeof callGeminiFlash = callGeminiFlash,
): Promise<{ query: string; translated: boolean }> {
  const q = String(query || '').trim();
  if (!q || !CJK.test(q)) return { query: q, translated: false };
  const hit = cache.get(q);
  if (hit) return { query: hit, translated: true };
  try {
    const raw = await llm({ system: SYSTEM, messages: [{ role: 'user', content: q }], maxTokens: 64, temperature: 0 } as any);
    const out = String(raw || '').split('\n')[0].replace(/^["'“”]+|["'“”]+$/g, '').trim();
    if (!out || CJK.test(out)) return { query: q, translated: false };
    if (cache.size > 2000) cache.clear();
    cache.set(q, out);
    return { query: out, translated: true };
  } catch {
    return { query: q, translated: false };
  }
}

/** Test helper. */
export function _resetSearchQueryCache(): void { cache.clear(); }
