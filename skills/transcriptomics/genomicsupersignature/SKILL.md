---
name: bioconductor-genomicsupersignature
description: Connect new gene expression profile with the relevant information from the existing databases, such as previous publications, MeSH terms, and gene sets.
when_to_use: Use when: Interpreting RNA-seq experiments by connecting results to public databases and published studies; Identifying biologically relevant patterns through comparison with Replicable Axes of Variation (RAVs); Discovering enriched gene sets and associated literature for identified expression patterns; Annotating gene expression signatures with MeSH terms and biological context; Studies seeking to leverage. Not for: De novo discovery of novel biological patterns without reference to existing databases; Studies with fewer than 8 samples; Microarray data or other non-RNA-seq expression platforms (tool specifically designed for RNA-seq); Real-time or streaming anal
user-invocable: false
---

## Workflows

### Standard Workflow

Validate a user's transcriptomic dataset against a pre-built RAVmodel to identify and biologically interpret the most relevant Replicable Axes of Variation (RAVs).

**Steps:**
1. Load the user's transcriptomic dataset (ensuring gene
2. Validate the dataset against the RAVmodel
3. Visualize the validation results
4. Extract the indices of the top validated RAVs
5. Interpret the validated RAVs
6. Search for specific biological themes using keyword-based

## Key Parameters

- {'parameter': 'using_ravmodel', 'scientific_meaning': 'Selects which pre-computed RAV model to use for comparison, determining which gene set annotations and database connections are available', 'typical_values': ['C2: MSigDB curated gene sets (version 7.1)', 'PLIERpriors: PLIER package gene sets (bloodCellMarkersIRISDMAP, svmMarkers, canonicalPathways)'], 'context_guidance': {'general_transcriptomics': 'C2 recommended for broad coverage of curated biological pathways', 'immune_cell_studies': 'PLIERpriors may be preferred for blood cell marker annotations', 'pathway_focused': 'C2 for comprehensive pathway coverage'}, 'evidence_url': 'extracted from rawText', 'quote': 'C2 : RAVmodel annotated with Molecular Signatures Database (MSigDB) curated gene sets (version 7.1). PLIERpriors : RAVmodel annotated with the three gene sets provided in the PLIER package - bloodCellMarkersIRISDMAP, svmMarkers, and canonicalPathways'}
- {'parameter': 'select_a_correlation_coefficient', 'scientific_meaning': 'Determines whether to use maximum correlation from top 8 PCs or average loading values for RAV matching', 'typical_values': ['Maximum PC correlation', 'Average Loading'], 'context_guidance': {'default': 'Maximum PC correlation captures strongest signal', 'exploratory': 'Average Loading provides more comprehensive view across components'}, 'evidence_url': 'extracted from rawText', 'quote': 'With Principal Component (PC), the maximum correlation coefficient from top 8 PCs for each avgLoading will be selected as an output. If you choose Average Loading, the Average Loading with the maximum correlation coefficient with each Principal Component will be in the output.'}
- {'parameter': 'output_format_of_validated_result', 'scientific_meaning': 'Controls whether output shows only maximum correlation coefficient per RAV or coefficients across all 8 principal components', 'typical_values': ['max: single maximum coefficient', 'all: coefficients for all 8 PCs'], 'context_guidance': {'summary_view': "Use 'max' for concise results focusing on strongest RAV matches", 'detailed_analysis': "Use 'all' to examine PC contributions and identify secondary patterns"}, 'evidence_url': 'extracted from rawText', 'quote': 'max will output the matrix containing only the maximum coefficient. To get the coefficient of all 8 PCs, set this argument to all.'}
- {'parameter': 'the_number_of_top_validated_ravs_to_check', 'scientific_meaning': 'Specifies how many top-ranked RAVs to include in output and analysis, controlling comprehensiveness of results', 'typical_values': 'Integer value (specific recommendations not provided in documentation)', 'context_guidance': {'focused_analysis': 'Lower values (e.g., 5-10) for most relevant RAVs', 'comprehensive_exploration': 'Higher values to explore broader biological context'}, 'evidence_url': 'extracted from rawText', 'quote': 'The number of top validated RAVs to check'}

## Result Interpretation

- {'guidance': "Interpret 'score' column as Pearson correlation coefficient between input dataset's top 8 PCs and RAVs; higher values indicate stronger biological relevance and pattern matching", 'evidence_url': 'extracted from rawText', 'quote': 'score: the maximum pearson correlation coefficient between the top 8 PCs of the input and RAVs'}
- {'guidance': "Use 'sw' (silhouette width) values to assess quality of RAV clustering; higher average silhouette width indicates more cohesive and reliable RAV definition", 'evidence_url': 'extracted from rawText', 'quote': 'sw: the average silhouette width of the RAV'}
- {'guidance': "Examine 'Genesets' output for enriched gene sets with adjusted p-value < 0.05; NES (normalized enrichment score) indicates direction and magnitude of enrichment", 'evidence_url': 'extracted from rawText', 'quote': 'Gene sets with the adjusted p-value < 0.05 are included. NES: normalized enrichment score (ES)'}
- {'guidance': "Review 'Literatures' output to identify published studies associated with matched RAVs, providing biological context and validation through existing literature", 'evidence_url': 'extracted from rawText', 'quote': 'RAVs connect different databases that are both linked to the originated study or associated with the RAV itself through the gene rankings of it.'}
- {'guidance': 'Consult HTML report for MeSH term word cloud and interactive visualization of validated RAVs to gain comprehensive overview of biological themes', 'evidence_url': 'extracted from rawText', 'quote': 'A html file with the summary of the main analyses by GenomicSuperSignature. It includes MeSH terms in word cloud and an interactive plot overviewing the validated RAVs'}

## Common Pitfalls

- {'mistake': 'Using scaled data as input', 'consequence': 'Reduced accuracy of correlation coefficients and RAV matching, suboptimal biological interpretation', 'recommendation': 'Apply log2 transformation but do NOT scale the data before input', 'evidence_url': 'extracted from rawText', 'quote': 'For the best result, we recommend a data transformation (e.g. log2) for the input to follow a normal distribution, while scaling is NOT recommended.'}
- {'mistake': 'Using raw count data without transformation', 'consequence': 'Data may not follow normal distribution, affecting correlation calculations and PC analysis', 'recommendation': 'Apply log2 transformation to count matrix before input', 'evidence_url': 'extracted from rawText', 'quote': 'For the best result, we recommend a data transformation (e.g. log2) for the input to follow a normal distribution'}
- {'mistake': 'Submitting studies with fewer than 8 samples', 'consequence': 'Tool cannot perform validation; insufficient data for robust principal component analysis', 'recommendation': 'Ensure minimum 8 samples in dataset before submission', 'evidence_url': 'extracted from rawText', 'quote': 'Currently for validation, inputs need at least eight samples.'}
- {'mistake': 'Misinterpreting correlation coefficient selection', 'consequence': 'Incorrect output format or missing information about PC contributions', 'recommendation': "Choose 'max' for single maximum coefficient per RAV, or 'all' to see coefficients across all 8 PCs", 'evidence_url': 'extracted from rawText', 'quote': 'max will output the matrix containing only the maximum coefficient. To get the coefficient of all 8 PCs, set this argument to all.'}

## Alternatives

- {'tool': 'Gene Set Enrichment Analysis (GSEA)', 'when_to_prefer_this': 'GenomicSuperSignature better when seeking to connect expression patterns to published studies and multiple databases simultaneously, with automatic RAV matching across 8 principal components', 'when_to_prefer_alternative': 'GSEA better for focused enrichment analysis of pre-defined gene sets without requiring database-wide comparison or when sample size is smaller', 'evidence_url': 'needs_verification', 'search_query': 'GenomicSuperSignature vs GSEA comparison RNA-seq interpretation'}
- {'tool': 'Pathway analysis tools (e.g., IPA, Reactome)', 'when_to_prefer_this': 'GenomicSuperSignature better for unbiased discovery of relevant biological contexts from public databases and literature integration', 'when_to_prefer_alternative': 'Pathway tools better for hypothesis-driven analysis of specific biological pathways', 'evidence_url': 'needs_verification', 'search_query': 'GenomicSuperSignature pathway analysis comparison'}
