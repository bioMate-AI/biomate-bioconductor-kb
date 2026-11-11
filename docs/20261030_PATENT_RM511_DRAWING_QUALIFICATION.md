# RM-511 primary drawing qualification — 30 October 2026

The exact RM-511 structure image has now been located and visually inspected. This resolves the missing-drawing and closure-route questions in the earlier recovery review. It does not establish a validated molecular graph or numerical prior.

## Primary-source join

The [published patent WO2024108198A2](https://patents.google.com/patent/WO2024108198A2/en) identifies RM-511 with SEQ ID NO:148 in its Formula II discussion. Immediately after the corresponding structure-introduction sentence, the HTML contains drawing ID `imgf000101_0001`. This anchors the image to the exact compound rather than to an adjacent generic formula. [Exact published drawing](https://patentimages.storage.googleapis.com/fa/98/ad/4b242244150ca2/imgf000101_0001.png).

The inspected drawing shows a direct S–S bond joining the two cysteine side chains. The macrocycle is therefore disulfide-linked, not an inferred head-to-tail amide or an unspecified choice among the neighboring generic formulas. It also depicts the N-terminal hydantoin-containing unit and a C-terminal primary amide. Wedge/dash bonds are present; their complete atom-by-atom assignment has not been transcribed or independently validated.

The long horizontal S–S line crosses other drawn groups without a junction marker; a drawing-to-graph process must not create bonds at these incidental crossings. The hydantoin unit must be transcribed from the explicit ring topology, rather than treated as an unknown residue or reduced to a generic N-terminal cap. No SMILES has been invented from the peptide name.

## Provenance and status

| Item | Exact inspected record |
|---|---|
| Original extraction ID | `35fcd616b1098727` |
| Original passage | `WO-2024108198-A2:76` (extraction window, not patent paragraph) |
| Image ID | `imgf000101_0001` |
| Image SHA-256 | `0eaf082a2b27d196142cdf30ea6094245088eaae3c56a6b8f27ce21192808e90` |
| Downloaded HTML SHA-256 | `b8138616375d981f6c38451f7fd661245f652fec5c5ab9729bba792202f4a22f` |
| Inspection copies | `/tmp/RM511-primary-drawing.png`, `/tmp/WO2024108198A2-source.html` |
| Review class | `AI_ASSISTED_CANDIDATE` |
| Graph / learned-conditioning / numeric-prior approval | None |

The new HTML hash identifies the live downloaded HTML, not the previously retained corpus text string. The older retained-text hash remains unchanged and refers to a different representation. The HTML references the image directly; the image's independently hashed bytes were inspected with the image viewer. Web PDF retrieval failed, but the linked source image was accessible. No chemical parsing, model execution, tests or scientific calculations were run.

## Remaining qualification

A subsequent graph transcription must preserve the hydantoin connectivity, all stereocentres, terminal amide, peptide backbone and cysteine disulfide. It then needs chemical validation on AWS and an independent comparison against the source drawing. Numerical activity is still unlinked in the audited extraction. Parent applicability, source/compound/scaffold/target exclusions and held-out independence also remain unresolved. In particular, the current generation constraint in `rules/spec.py` requires 2–6 N-methyl amides; the inspected drawing does not visibly show such N-methyl substitutions. This is a source-reading concern, not a computed descriptor result. Do not relax the frozen constraint or assume the molecule is a valid parent merely because its closure is now known. Consequently this evidence is a source-qualified closure observation attached to a review candidate, not an accepted training example or an estimated design improvement.

## Implementation clarification: output constraints versus prefix parents

Subsequent inspection of `hybrid/model.py::sample` and `hybrid/run_stage1.py::FrozenParentProtocol` establishes that C constrains completed proposals. The frozen parent pool enforces source/task metadata and exclusions, but does not require the full parent molecule to pass C. Therefore an out-of-C source molecule is not automatically prohibited as a prefix parent by the code. Earlier references here to C-valid generation parents describe a possible narrower study design, not an implemented universal eligibility rule. Such a restriction must be explicitly prespecified if adopted. Any parent still needs an exact reviewed mapping, evidence applicability and split clearance; whether its retained prefix can yield valid completions remains an empirical question. None of these candidates is promoted by this clarification.
