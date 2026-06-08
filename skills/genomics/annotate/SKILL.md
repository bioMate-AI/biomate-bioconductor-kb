---
name: bioconductor-annotate
description: This tool uses the label-tree function from HyPhy to annotate a phylogenetic tree. It allows users to select a subset of leaves using either a regular expression or a list of sequence names, and then apply a specified label to these selecte
when_to_use: Use when: Annotating specific clades or lineages in pre-computed phylogenetic trees for visualization; Marking monophyletic groups identified through external analysis; Preparing trees for publication with labeled evolutionary groups; Subsetting and labeling sequences based on taxonomic or functional criteria; Creating customized tree visualizations with clade-specific annotations. Not for: Initial phylogenetic tree construction (use phylogenetic inference tools instead); Sequence alignment or quality control; Automated clade detection without prior knowledge (use clade detection algorithms); Large-scale batch annotation without scripti
user-invocable: false
---

# annotate

This tool uses the label-tree function from HyPhy to annotate a phylogenetic tree. It allows users to select a subset of leaves using either a regular expression or a list of sequence names, and then apply a specified label to these selected branches. The tool also provides options for rerooting the tree, inverting the selection, and defining strategies for labeling internal and leaf nodes. This functionality is crucial for customizing tree visualizations and focusing on specific evolutionary ev

## When to Use

- Annotating specific clades or lineages in pre-computed phylogenetic trees for visualization
- Marking monophyletic groups identified through external analysis
- Preparing trees for publication with labeled evolutionary groups
- Subsetting and labeling sequences based on taxonomic or functional criteria
- Creating customized tree visualizations with clade-specific annotations

## When NOT to Use

- Initial phylogenetic tree construction (use phylogenetic inference tools instead)
- Sequence alignment or quality control
- Automated clade detection without prior knowledge (use clade detection algorithms)
- Large-scale batch annotation without scripting capability

## Scientific Assumptions

- {'assumption': 'Input tree is in valid Newick format with properly formatted leaf node identifiers', 'violation_context': 'Malformed Newick syntax, special characters in node names, or inconsistent formatting will cause parsing errors or failed selection', 'evidence_url': 'extracted from rawText', 'quote': 'Input tree: The tree to annotate (Newick format)'}
- {'assumption': 'Leaf node names are consistent and match the regular expression or sequence list provided', 'violation_context': 'Typos, case sensitivity mismatches, or naming convention changes will result in failed or partial selection', 'evidence_url': 'extracted from rawText', 'quote': 'A regular expression or a list of sequence names to define the subset of leaves for annotation'}
- {'assumption': 'Tree topology is biologically meaningful and correctly inferred prior to annotation', 'violation_context': 'Errors in phylogenetic inference will propagate to annotation; tool does not validate tree quality', 'evidence_url': 'needs_verification', 'search_query': 'phylogenetic tree quality validation assumptions'}
- {'assumption': 'Selected node for rerooting exists in the tree and is a valid internal or leaf node', 'violation_context': 'Invalid node specification will cause rerooting failure or unexpected tree structure', 'evidence_url': 'extracted from rawText', 'quote': "Reroot the tree on this node ('None' to skip rerooting)"}
- {'assumption': 'Labeling strategies (internal nodes, leaf nodes) are appropriate for the downstream analysis or visualization tool', 'violation_context': 'Incompatible labeling strategies may produce annotations that cannot be properly interpreted or visualized', 'evidence_url': 'needs_verification', 'search_query': 'phylogenetic tree annotation labeling strategy compatibility'}

## Common Pitfalls

- {'mistake': 'Using incorrect regular expression syntax that fails to match intended leaf nodes', 'consequence': 'Annotation applied to wrong or no sequences; incorrect clade labeling', 'recommendation': "Test regular expressions against actual leaf node names in the Newick file; use simple patterns initially (e.g., 'species_name.*' for prefix matching)", 'evidence_url': 'needs_verification', 'search_query': 'regular expression phylogenetic tree leaf node matching tutorial'}
- {'mistake': 'Applying conflicting labeling strategies to internal and leaf nodes without understanding the output structure', 'consequence': 'Ambiguous or redundant annotations; difficult tree interpretation', 'recommendation': "Clearly define labeling strategy based on analysis goals: use 'All descendants' for clade-level annotation, 'Some descendants' for specific subsets, or 'None' to avoid internal node labeling", 'evidence_url': 'needs_verification', 'search_query': 'phylogenetic tree internal node labeling strategy best practices'}
- {'mistake': 'Rerooting tree on inappropriate node without understanding phylogenetic implications', 'consequence': 'Altered evolutionary relationships; misleading clade definitions', 'recommendation': 'Only reroot if necessary for analysis; ensure rerooting node is valid and biologically meaningful (e.g., outgroup placement)', 'evidence_url': 'needs_verification', 'search_query': 'phylogenetic tree rerooting best practices evolutionary analysis'}
- {'mistake': 'Inverting selection without verifying which sequences are actually selected', 'consequence': 'Labeling opposite clade than intended', 'recommendation': 'Verify selection before inversion; test with small subset first; review annotate report output', 'evidence_url': 'needs_verification', 'search_query': 'phylogenetic tree selection inversion verification'}

## Key Parameters

- {'parameter': 'regular_expression', 'scientific_meaning': 'Pattern matching criterion to identify leaf nodes for annotation; enables flexible selection of sequences based on naming conventions', 'typical_values': "Species prefixes (e.g., 'Human.*'), taxonomic patterns (e.g., '.*virus.*'), or specific identifiers", 'context_guidance': {'scenario_clade_annotation': 'Use species or genus prefix patterns to mark monophyletic groups', 'scenario_functional_subset': 'Use functional category prefixes if sequences are named accordingly', 'scenario_single_sequence': 'Use exact name or unique identifier pattern'}, 'evidence_url': 'extracted from rawText', 'quote': 'Use the following regular expression to select a subset of leaves'}
- {'parameter': 'strategy_for_labeling_internal_nodes', 'scientific_meaning': 'Determines how internal nodes (representing ancestral lineages) are labeled when their descendants are selected; controls annotation granularity', 'typical_values': ['None: No internal node labeling', 'All descendants: Label all descendants of selected internal node', 'All descendants, no MRCA: Label descendants excluding most recent common ancestor', 'Some descendants: Label specific descendants', 'Parsimony: Label based on parsimony principle'], 'context_guidance': {'scenario_clade_definition': "Use 'All descendants' to mark entire monophyletic group", 'scenario_exclude_root': "Use 'All descendants, no MRCA' when MRCA should not be labeled", 'scenario_specific_lineages': "Use 'Some descendants' for partial clade annotation", 'scenario_minimal_annotation': "Use 'None' to label only leaf nodes"}, 'evidence_url': 'extracted from rawText', 'quote': 'Strategy for labeling internal nodes: None, All descendants, All descendants no MRCA, Some descendants, Parsimony'}
- {'parameter': 'strategy_for_labeling_selected_leaves', 'scientific_meaning': 'Controls whether selected leaf nodes receive the annotation label; determines if terminal taxa are explicitly marked', 'typical_values': ['Label: Apply specified label to selected leaf nodes', 'Skip: Do not label leaf nodes'], 'context_guidance': {'scenario_explicit_marking': "Use 'Label' when leaf-level annotation is important for visualization", 'scenario_clade_only': "Use 'Skip' when only clade (internal node) annotation is needed"}, 'evidence_url': 'extracted from rawText', 'quote': 'Strategy for labeling selected leaves: Label or Skip'}
- {'parameter': 'reroot_the_tree_on_this_node', 'scientific_meaning': 'Specifies node for tree rerooting; changes root position and affects branch length interpretation and evolutionary relationships', 'typical_values': "Valid node identifier from tree (typically outgroup or specific internal node); 'None' to skip rerooting", 'context_guidance': {'scenario_outgroup_rooting': 'Specify outgroup sequence name to establish correct evolutionary polarity', 'scenario_no_rerooting': "Use 'None' if tree is already correctly rooted"}, 'evidence_url': 'extracted from rawText', 'quote': "Reroot the tree on this node ('None' to skip rerooting)"}
- {'parameter': 'invert_selection', 'scientific_meaning': 'Reverses the selection logic; applies annotation to all sequences NOT matching the selection criterion', 'typical_values': 'Boolean (yes/no or true/false)', 'context_guidance': {'scenario_complement_set': 'Use when it is easier to define what to exclude than what to include', 'scenario_outgroup_marking': 'Use to mark all sequences except a specific clade'}, 'evidence_url': 'extracted from rawText', 'quote': 'Invert selection'}

## Result Interpretation

- {'guidance': 'Examine the labeled tree output (Newick format) to verify that annotations were applied to correct nodes; check that branch labels match intended clade definitions', 'evidence_url': 'extracted from rawText', 'quote': 'Output: Labeled tree: A Newick file containing the annotated phylogenetic tree'}
- {'guidance': 'Review the Annotate Report (Markdown format) for summary of annotation operations; verify number of selected sequences and labeling strategy applied', 'evidence_url': 'extracted from rawText', 'quote': 'Annotate Report: A Markdown file with a summary of the analysis'}
- {'guidance': 'Validate that regular expression or sequence list correctly identified intended leaf nodes by cross-referencing report with original tree structure', 'evidence_url': 'needs_verification', 'search_query': 'phylogenetic tree annotation validation best practices'}
- {'guidance': 'Confirm that rerooting (if applied) did not inadvertently alter evolutionary relationships or branch length interpretations', 'evidence_url': 'needs_verification', 'search_query': 'phylogenetic tree rerooting validation interpretation'}

## Alternatives

- {'tool': 'FigTree', 'when_to_prefer_this': 'Annotate tool preferred when programmatic/batch annotation of multiple trees is needed or when integration into Galaxy workflows is required', 'when_to_prefer_alternative': 'FigTree preferred for interactive, GUI-based tree annotation and visualization with real-time editing', 'evidence_url': 'needs_verification', 'search_query': 'FigTree phylogenetic tree annotation software comparison'}
- {'tool': 'ETE Toolkit', 'when_to_prefer_this': 'Annotate tool preferred for Galaxy-integrated workflows; simpler interface for basic labeling tasks', 'when_to_prefer_alternative': 'ETE Toolkit preferred for complex programmatic tree manipulation, advanced visualization, and Python-based scripting', 'evidence_url': 'needs_verification', 'search_query': 'ETE Toolkit phylogenetic tree annotation comparison HyPhy'}
- {'tool': 'Dendroscope', 'when_to_prefer_this': 'Annotate tool preferred for automated batch processing and workflow integration', 'when_to_prefer_alternative': 'Dendroscope preferred for interactive visualization and manual clade annotation with advanced graphics', 'evidence_url': 'needs_verification', 'search_query': 'Dendroscope phylogenetic tree annotation tool comparison'}

## Citations

- {"pmid": "41317327", "doi": "10.1016/j.xpro.2025.104221", "title": "Protocol to annotate and automate single-cell instance segmentation on stimulated Raman histology using deep learning.", "authors": ["Bhattacharya A", "Landgraf E", "Jiang C", "Chowdury A", "Kondepudi A"], "journal": "STAR Protoc", "year": 2025, "abstract": null, "citation_count": null, "pub_type": "tool", "url": "https://pubmed.ncbi.nlm.nih.gov/41317327"}
- {'pmid': '41342577', 'doi': '10.1093/gigascience/giaf121', 'title': 'Toward a standardized framework for pangenome graph evaluation: assessing crop plant pangenome variation graph construction from multiple assemblies.', 'authors': ['Kopalli V', 'Arslan K', 'Morales-Díaz N', 'Zanini SF', 'Golicz AA'], 'journal': 'Gigascience', 'year': 2025, 'abstract': None, 'citation_count': None, 'pub_type': 'benchmark', 'url': 'https://pubmed.ncbi.nlm.nih.gov/41342577'}

## References

- Homepage: Not provided in documentation
- Documentation: Galaxy tool documentation (rawText provided)
- needs_verification - HyPhy label-tree function publication
