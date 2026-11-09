# GIP component source qualification — 30 October 2026

## Review status

This targeted primary-source reading extends [the prior recovery review](20261029_PATENT_SOURCE_RECOVERY_REVIEW.md) for GIP-057 (`ba134a47b2b054df`) and GIP-126 (`fa4169d82a10b247`). Both remain **AI_ASSISTED_CANDIDATE**, with **method_prior_eligible=false**. Original extraction records are unchanged. This note qualifies textual definitions and attachment conventions, not complete chemical graphs.

## Newly recovered primary-source details

All locations below refer to EP4170347A1, printed PDF pages; PDF page numbering agrees with printed numbering.

| Item | Recovered definition or constraint | Primary location |
|---|---|---|
| Ttds | `1,13-diamino-4,7,10-trioxatridecan-succinamic acid`. | [Table 5, p.221](https://patentimages.storage.googleapis.com/2c/73/76/9cabcd3913f82a/EP4170347A1.pdf#page=221) |
| 3MeBn | Defined as 3-methylbenzylidene derived from 1,3-xylene. The adjacent 3MeBz entry instead means 3-methylbenzoyl; these must remain distinct tokens. | [Table 5, p.203](https://patentimages.storage.googleapis.com/2c/73/76/9cabcd3913f82a/EP4170347A1.pdf#page=203) |
| Cycle attachments | Paragraph [0316] assigns the parenthesized linker to both bracket-boundary side chains; sulfhydryl-bearing residues form thioethers. Applying this convention to the named Cys…Cys products supports two cysteine-side-chain attachments, not a disulfide or head-to-tail amide. | [Paragraphs [0314]–[0316], p.225](https://patentimages.storage.googleapis.com/2c/73/76/9cabcd3913f82a/EP4170347A1.pdf#page=225) |
| GIP-057 biotin branch | Parenthesized Lys substitution uses an amide to its side-chain epsilon amino group. | [Paragraphs [0309]–[0310], p.224](https://patentimages.storage.googleapis.com/2c/73/76/9cabcd3913f82a/EP4170347A1.pdf#page=224) |
| Compound drawings | GIP-057 formula is located on p.63; the GIP-126 entry/formula spans pp.92–93. Their linked source images were subsequently inspected as recorded below. | [GIP-057, p.63](https://patentimages.storage.googleapis.com/2c/73/76/9cabcd3913f82a/EP4170347A1.pdf#page=63); [GIP-126, pp.92–93](https://patentimages.storage.googleapis.com/2c/73/76/9cabcd3913f82a/EP4170347A1.pdf#page=92) |

Table 5's introduction permits exemplary installation reagents alongside building blocks; a depicted precursor cannot automatically become the installed residue. [Paragraph [0286], p.202](https://patentimages.storage.googleapis.com/2c/73/76/9cabcd3913f82a/EP4170347A1.pdf#page=202).

## Remaining qualification work

The useful change is a source-backed component dictionary and attachment-class constraint. A future reviewed sidecar should preserve the raw extraction hash, record ID, compound identity, exact source location, original token, proposed definition, and reviewer decision separately. No alias replacement should overwrite the original passage.

Before either record enters a graph-based prior, a reviewer must approve a complete atom-level transcription, including installed Ttds orientation, conjugate attachment atoms, stereochemistry, terminal groups and linker bonds. Neither parser success nor agreement with a chemical name substitutes for that review.

## Direct source-image follow-up

The PDF screenshot route failed, but ordinary HTTPS retrieval of the [primary HTML](https://patents.google.com/patent/EP4170347A1/en) and its linked PNGs succeeded. The actual PNGs were opened and visually inspected; no image transformation or graph conversion was performed. The compound heading precedes its formula image: GIP-057 maps to `chem0119`/`ib0119`, and GIP-126 to `chem0188`/`ib0188` (not the preceding image on the same HTML line).

Both drawings show the two sulfur–benzyl connections. GIP-057 shows the C-terminal spacer continuing to amidated lysine with its biotin side-chain branch. GIP-126 shows a DOTA acetate-arm amide to the spacer, its succinyl end attached to Tyr nitrogen, and an amidated terminal cysteine. These observations support attachment topology, not an approved stereochemical graph.

| Retrieved asset | SHA-256 of exact retrieved bytes |
|---|---|
| HTML, `/tmp/ep4170347-source.html` | `4a7c96b5540f3cf5bd8eed820981931aec3b289c3a10b8457c359401d5d74931` |
| [GIP-057 source PNG, imgb0119](https://patentimages.storage.googleapis.com/8a/1d/10/729d912a61103e/imgb0119.png), `/tmp/gip057-source.png` | `55f2650d015e3501b26b2533fec587cb9d1971d371d6232138a563c53b006326` |
| [GIP-126 source PNG, imgb0188](https://patentimages.storage.googleapis.com/2f/2a/0a/f735995300358d/imgb0188.png), `/tmp/gip126-source.png` | `bd7388dc500cca07524a97932419f6475347f932faf25df572c7e03dfe010251` |

These retrieval hashes identify this follow-up's bytes; the HTML hash does not replace the prior archive's extracted-text hash. Local `/tmp` copies are temporary, not a durable evidence archive. The remaining blocker has narrowed from unavailable drawings to reviewed graph transcription and qualification. Candidate status and exclusion from method priors remain unchanged.

No chemical parsing, graph reconstruction, tests, model execution, paid extraction or new scientific computation was performed. No assay qualification, eligibility promotion or aggregate recovery-rate claim follows from this note.
