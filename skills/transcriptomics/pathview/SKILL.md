---
name: bioconductor-pathview
description: Pathview is a stand-alone software package for pathway based data integration and visualization.
when_to_use: Use when: Integrating gene expression data with metabolic pathway visualization; Multi-omics visualization combining gene and compound data on same pathway; Pathway-based interpretation of differential expression or association studies; Metagenomic data analysis using KEGG ortholog mapping; Preserving KEGG pathway metadata including spatial, temporal, tissue/cell type information; Generating both KEGG nativ. Not for: Pathway discovery or inference from data (tool requires pre-existing KEGG pathways); Organisms with limited KEGG pathway coverage; Data with gene IDs not mappable to KEGG database; Users requiring custom pathway topology not available in KEGG; Real-t
user-invocable: false
---

# pathview

Pathview is a stand-alone software package for pathway based data integration and visualization.

## When to Use

- Integrating gene expression data with metabolic pathway visualization
- Multi-omics visualization combining gene and compound data on same pathway
- Pathway-based interpretation of differential expression or association studies
- Metagenomic data analysis using KEGG ortholog mapping
- Preserving KEGG pathway metadata including spatial, temporal, tissue/cell type information
- Generating both KEGG native view and Graphviz topology views for comprehensive pathway understanding

## When NOT to Use

- Pathway discovery or inference from data (tool requires pre-existing KEGG pathways)
- Organisms with limited KEGG pathway coverage
- Data with gene IDs not mappable to KEGG database
- Users requiring custom pathway topology not available in KEGG
- Real-time or streaming pathway analysis

## Scientific Assumptions

- {'assumption': 'Gene IDs are uniquely mappable to KEGG gene IDs or KEGG ortholog IDs', 'violation_context': 'When using non-standard gene ID systems, ambiguous gene identifiers, or genes not present in KEGG database. Particularly problematic for non-model organisms with incomplete KEGG coverage.', 'evidence_url': 'extracted from rawText', 'quote': 'Here gene id is a generic concepts, including multiple types of gene, transcript and protein uniquely mappable to KEGG gene IDs'}
- {'assumption': 'Compound IDs are mappable to KEGG compound IDs or one of 20+ CHEMBL database ID types', 'violation_context': 'When using proprietary compound identifiers, custom metabolite IDs, or compounds not in KEGG/CHEMBL databases', 'evidence_url': 'extracted from rawText', 'quote': 'The format is similar to the gene data table, except named with IDs mappable to KEGG compound IDs. Over 20 types of IDs included in CHEMBL database can be used here.'}
- {'assumption': 'KEGG pathway topology and annotations are accurate and current for the organism/pathway of interest', 'violation_context': 'When KEGG pathways are outdated, incomplete, or contain errors. Particularly relevant for newly discovered pathways or organisms with limited curation.', 'evidence_url': 'needs_verification', 'search_query': 'KEGG pathway curation accuracy limitations'}
- {'assumption': 'Data values are appropriate for the visualization method (continuous values for color gradients, discrete values for categorical mapping)', 'violation_context': "When mixing incompatible data types or using inappropriate value ranges that don't map well to color scales", 'evidence_url': 'extracted from rawText', 'quote': 'various data attributes and formats, i.e. continuous/discrete data, matrices/vectors, single/multiple samples etc'}

## Common Pitfalls

- {'mistake': 'Using gene IDs not mappable to KEGG database', 'consequence': 'Genes will not be visualized on pathways; data integration will fail', 'recommendation': 'Convert gene IDs to one of the 10+ supported KEGG-mappable ID types (Entrez, Ensembl, etc.) before input', 'evidence_url': 'extracted from rawText', 'search_query': 'KEGG gene ID conversion tools'}
- {'mistake': 'Providing compound data with IDs not in KEGG or CHEMBL databases', 'consequence': 'Metabolites will not map to pathway nodes', 'recommendation': 'Use one of the 20+ CHEMBL-compatible compound ID types or convert to KEGG compound IDs', 'evidence_url': 'extracted from rawText', 'search_query': 'KEGG compound ID mapping CHEMBL'}
- {'mistake': 'Mismatched sample sizes between gene and compound data without understanding padding behavior', 'consequence': 'Unexpected NA values and missing color mapping in visualization', 'recommendation': 'Understand that when gene and compound data are paired with different sample sizes (m>n), extra NA columns are added to equalize sizes', 'evidence_url': 'extracted from rawText', 'quote': "When let sample sizes of gene and compound be m and n, when m>n, extra columns of NA's (mapped to no color) will be added to make the sample size the same"}

## Key Parameters

- {'parameter': 'KEGG pathway ID', 'scientific_meaning': 'Specifies which KEGG pathway to visualize; must be 5-digit ID without 3-letter species code', 'typical_values': 'Examples: 00010 (Glycolysis), 00020 (Citric acid cycle), 01100 (Metabolic pathways)', 'context_guidance': {'metabolic_studies': 'Use metabolic pathway IDs (00xxx series)', 'signaling_studies': 'Use signaling pathway IDs (04xxx series)', 'disease_studies': 'Use disease pathway IDs (05xxx series)'}, 'evidence_url': 'extracted from rawText', 'quote': 'KEGG pathway ID with 5 digits and without the 3 letter KEGG species code'}
- {'parameter': 'Gene data format', 'scientific_meaning': 'Controls how gene measurements (fold change, p-values, expression levels) are interpreted and mapped to pathway nodes', 'typical_values': 'Continuous values (fold change, log2FC), discrete values (p-values, adjusted p-values), expression levels', 'context_guidance': {'differential_expression': 'Use fold change or log2 fold change values', 'association_studies': 'Use p-values or -log10(p-values)', 'expression_profiling': 'Use normalized expression levels'}, 'evidence_url': 'extracted from rawText', 'quote': 'It should be a table with first column being the gene ids and other being information (p-value, fold change, levels, etc) from one or several samples'}
- {'parameter': 'Gene and compound data pairing', 'scientific_meaning': 'Determines whether gene and metabolite data are visualized as separate or integrated states on same pathway nodes', 'typical_values': 'Paired (true/false)', 'context_guidance': {'multi_omics_integration': 'Set to true when analyzing coordinated gene-metabolite changes', 'separate_analysis': 'Set to false when visualizing gene and compound data independently'}, 'evidence_url': 'extracted from rawText', 'quote': 'Should multiple states of gene or compond data be intergrated and plotted in the same graph?'}
- {'parameter': 'Header presence in gene/compound data', 'scientific_meaning': 'Indicates whether first line contains sample names (true) or data (false); affects data parsing', 'typical_values': 'Boolean (true/false)', 'context_guidance': {'labeled_samples': 'Set to true when sample names are meaningful for interpretation', 'unlabeled_samples': 'Set to false for simple numeric sample indices'}, 'evidence_url': 'extracted from rawText', 'quote': 'Does the file have header (a first line with sample names)?'}

## Result Interpretation

- {'guidance': 'KEGG view output preserves all KEGG pathway metadata including spatial and temporal information, tissue/cell types, inputs, outputs and connections. This view is optimal for human interpretation of pathway biology and understanding biological context.', 'evidence_url': 'extracted from rawText', 'quote': 'KEGG view keeps all the meta-data on pathways, spacial and temporal information, tissue/cell types, inputs, outputs and connections. This is important for human reading and interpretation of pathway biology.'}
- {'guidance': 'Graphviz view output provides better control of node and edge attributes, clearer visualization of pathway topology, and better understanding of pathway analysis statistics. Use this view for detailed statistical interpretation and topology analysis.', 'evidence_url': 'extracted from rawText', 'quote': 'Graphviz view provides better control of node and edge attributes, better view of pathway topology, better understanding of the pathway analysis statistics.'}
- {'guidance': 'Gene nodes are colored based on provided data values (fold change, p-values, expression levels). Compound nodes are similarly colored based on metabolite measurements. When multiple samples are provided, nodes are sliced into multiple pieces corresponding to number of samples.', 'evidence_url': 'extracted from rawText', 'quote': 'Gene or compound nodes will be sliced into multiple pieces corresponding to the number of states in the data'}
- {'guidance': 'NA values in compound data (when sample sizes differ between gene and compound datasets) are mapped to no color in visualization, indicating missing or unmeasured data.', 'evidence_url': 'extracted from rawText', 'quote': "extra columns of NA's (mapped to no color) will be added to make the sample size the same"}

## Alternatives

- {'tool': 'Cytoscape with pathway plugins', 'when_to_prefer_this': 'Pathview better when requiring automated KEGG pathway integration, multiple sample visualization, and native KEGG metadata preservation', 'when_to_prefer_alternative': 'Cytoscape better when requiring custom pathway editing, complex network analysis beyond pathway visualization, or non-KEGG pathway sources', 'evidence_url': 'needs_verification', 'search_query': 'Pathview vs Cytoscape pathway visualization comparison'}
- {'tool': 'DAVID pathway analysis', 'when_to_prefer_this': 'Pathview better for direct data visualization on pathways and multi-omics integration', 'when_to_prefer_alternative': 'DAVID better for pathway enrichment analysis and statistical testing of pathway significance', 'evidence_url': 'needs_verification', 'search_query': 'Pathview DAVID pathway analysis comparison'}
- {'tool': 'KEGGscape', 'when_to_prefer_this': 'Pathview better for standalone analysis and multiple sample integration', 'when_to_prefer_alternative': 'KEGGscape better when requiring Cytoscape integration and interactive network manipulation', 'evidence_url': 'needs_verification', 'search_query': 'Pathview KEGGscape comparison pathway visualization'}

## Citations

- Luo W, Brouwer C. (2013). Pathview: an R/Bioconductor package for pathway-based data integration and visualization. Bioinformatics, 29(14):1830-1831. [PMID:23740750](https://pubmed.ncbi.nlm.nih.gov/23740750) doi:10.1093/bioinformatics/btt285

## References

- Homepage: Not provided in documentation
- Documentation: Galaxy tool wrapper documentation (rawText provided)
- {'citation': 'Zhang and Wiemann, 2009 - KEGGgraph paper', 'url': 'needs_verification', 'search_query': 'Zhang Wiemann 2009 KEGGgraph'}