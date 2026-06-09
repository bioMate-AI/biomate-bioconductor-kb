---
name: bioconductor-reactomepa
description: Reactome is a free, open-source, curated and peer-reviewed pathway database. Their goal is to provide intuitive bioinformatics tools for the visualization, interpretation and analysis of pathway knowledge.
when_to_use: Use when: Identifying significantly enriched Reactome pathways from differentially expressed gene lists; Functional interpretation of RNA-seq or microarray results; Comparative pathway analysis across supported model organisms; Studies requiring curated, peer-reviewed pathway annotations. Not for: Pathway analysis requiring detailed network topology or edge information; Studies needing pathway visualization beyond enrichment statistics; Organisms outside the seven supported species; Gene lists without Entrez ID mapping; Analyses requiring alte
user-invocable: false
---

# ReactomePA

Reactome is a free, open-source, curated and peer-reviewed pathway database. Their goal is to provide intuitive bioinformatics tools for the visualization, interpretation and analysis of pathway knowledge.

## When to Use

- Identifying significantly enriched Reactome pathways from differentially expressed gene lists
- Functional interpretation of RNA-seq or microarray results
- Comparative pathway analysis across supported model organisms
- Studies requiring curated, peer-reviewed pathway annotations

## When NOT to Use

- Pathway analysis requiring detailed network topology or edge information
- Studies needing pathway visualization beyond enrichment statistics
- Organisms outside the seven supported species
- Gene lists without Entrez ID mapping
- Analyses requiring alternative pathway databases (KEGG, Biocarta, etc.)

## Scientific Assumptions

- {'assumption': 'Input gene list represents true biological signal (differentially expressed genes) rather than technical artifacts', 'violation_context': 'When DE analysis used inappropriate statistical methods, insufficient replicates, or poor quality control', 'evidence_url': 'needs_verification', 'search_query': 'differential expression analysis quality control best practices'}
- {'assumption': 'Reactome pathway annotations are complete and accurate for the organism being studied', 'violation_context': 'Newly discovered pathways or organism-specific variations not yet curated in Reactome', 'evidence_url': 'needs_verification', 'search_query': 'Reactome pathway database coverage completeness'}
- {'assumption': 'Gene set enrichment follows hypergeometric distribution (genes are randomly distributed across pathways)', 'violation_context': 'When genes have strong co-expression patterns or functional clustering independent of pathway membership', 'evidence_url': 'needs_verification', 'search_query': 'hypergeometric test pathway enrichment assumptions'}
- {'assumption': 'Multiple testing correction appropriately controls error rate for the number of pathways tested', 'violation_context': 'When pathway annotations are highly correlated or overlapping, standard corrections may be conservative', 'evidence_url': 'needs_verification', 'search_query': 'multiple testing correction correlated hypotheses pathway analysis'}
- {'assumption': 'Entrez ID mapping is accurate and one-to-one between input genes and Reactome annotations', 'violation_context': 'When gene ID conversions are outdated or when one gene maps to multiple Entrez IDs', 'evidence_url': 'needs_verification', 'search_query': 'Entrez gene ID mapping accuracy issues'}

## Common Pitfalls

- {'mistake': 'Using gene symbols or other identifiers instead of Entrez IDs', 'consequence': 'Tool will fail to match genes to Reactome pathways, resulting in no enrichment results or errors', 'recommendation': "Convert gene identifiers to Entrez IDs before input. Use tools like 'Gene ID Converter' or similar ID mapping tools", 'evidence_url': 'provided in rawText', 'search_query': 'Entrez gene ID conversion tools'}
- {'mistake': 'Analyzing organisms not in the supported list', 'consequence': 'Tool will not run or produce incorrect results due to missing organism-specific pathway annotations', 'recommendation': 'Verify organism is in supported list: human, rat, mouse, C. elegans, yeast, zebrafish, or fly', 'evidence_url': 'provided in rawText'}
- {'mistake': 'Not adjusting p-value threshold for multiple testing correction', 'consequence': 'Inflated false positive rate when reporting enriched pathways', 'recommendation': 'Use appropriate multiple testing correction method (default BH/Benjamini-Hochberg recommended for FDR control)', 'evidence_url': 'provided in rawText', 'search_query': 'multiple testing correction pathway enrichment best practices'}
- {'mistake': 'Including very small or very large gene sets without filtering', 'consequence': 'Spurious enrichment from gene sets with few genes or loss of specificity from very large sets', 'recommendation': 'Use default gene set size filtering (10-500 genes) or adjust based on biological context', 'evidence_url': 'provided in rawText'}

## Key Parameters

- {'parameter': 'P-value threshold', 'scientific_meaning': 'Cutoff for determining statistical significance of pathway enrichment. Controls false positive rate.', 'typical_values': '0.05 (default), 0.01 for stringent analysis, 0.1 for exploratory analysis', 'context_guidance': {'large_gene_lists': '0.05 or more stringent', 'small_gene_lists': '0.05-0.1', 'exploratory_analysis': '0.1', 'publication_quality': '0.05 with multiple testing correction'}, 'evidence_url': 'provided in rawText', 'quote': 'This is the cutoff p-value to determine significant enrichment of a pathway. Default is 0.05.'}
- {'parameter': 'Method to adjust pathway p-values for multiple testing', 'scientific_meaning': 'Statistical correction for multiple hypothesis testing to control family-wise error rate or false discovery rate', 'typical_values': 'BH (Benjamini-Hochberg), holm, hochberg, hommel, bonferroni, BY, fdr, none', 'context_guidance': {'recommended': 'BH (default) - controls FDR, good balance between sensitivity and specificity', 'conservative': 'bonferroni - controls family-wise error rate, most stringent', 'exploratory': 'none - no correction, highest sensitivity but highest false positive rate'}, 'evidence_url': 'provided in rawText', 'quote': "Choose one method to adjust pathway p-values. Included methods are: 'BH', 'holm', 'hochberg', 'hommel', 'bonferroni', 'BY', 'fdr' and 'none'. Default is 'BH'."}
- {'parameter': 'Minimum and maximum size of each geneSet', 'scientific_meaning': 'Filters gene sets by size to avoid spurious enrichment from very small sets or loss of specificity from very large sets', 'typical_values': 'Minimum: 5-15 genes, Maximum: 300-500 genes (default 10-500)', 'context_guidance': {'default': '10-500 genes - balanced approach', 'stringent': '15-300 genes - removes very small and very large sets', 'exploratory': '5-1000 genes - more permissive'}, 'evidence_url': 'provided in rawText', 'quote': 'Set minimum and maximum size of each gene set to be included in the analysis. Default are 10 and 500.'}
- {'parameter': 'Convert gene ID to SYMBOL', 'scientific_meaning': 'Option to convert Entrez IDs to human-readable gene symbols in output for interpretation', 'typical_values': 'Yes or No (default: No)', 'context_guidance': {'publication': 'Yes - improves readability for figures and tables', 'downstream_analysis': 'No - maintain Entrez IDs for computational pipelines', 'interpretation': 'Yes - easier to identify genes of interest'}, 'evidence_url': 'provided in rawText', 'quote': 'If you want to convert entrez gene ID to gene SYMBOL name, choose Yes. Default: No.'}

## Result Interpretation

- {'guidance': 'Output CSV contains enriched pathways with columns: ID (Reactome pathway ID), Description (pathway name), GeneRatio (number of input genes in pathway / total input genes), BgRatio (pathway size / total Reactome genes). Higher GeneRatio indicates stronger enrichment. Pathways are ranked by adjusted p-value.', 'evidence_url': 'provided in rawText', 'quote': 'A csv file including all enriched pathways. Example: ID, Description, GeneRatio, BgRatio'}
- {'guidance': 'GeneRatio represents the proportion of your input genes that map to each pathway. A GeneRatio of 22/326 means 22 of your 326 input genes are in that pathway. Higher ratios indicate more of your genes are involved in that pathway.', 'evidence_url': 'provided in rawText', 'search_query': 'pathway enrichment GeneRatio interpretation'}
- {'guidance': 'BgRatio represents the background pathway size relative to total Reactome genes. This helps assess whether enrichment is due to pathway size bias. Compare GeneRatio to BgRatio to evaluate enrichment strength.', 'evidence_url': 'provided in rawText', 'search_query': 'pathway enrichment BgRatio background ratio interpretation'}
- {'guidance': 'Validate enriched pathways by: (1) checking biological relevance to experimental conditions, (2) examining which genes drive enrichment, (3) comparing to literature on pathway involvement in your biological system', 'evidence_url': 'needs_verification', 'search_query': 'pathway enrichment result validation best practices'}

## Alternatives

- {'tool': 'clusterProfiler', 'when_to_prefer_this': 'ReactomePA when specifically using Reactome pathway database and working with supported organisms', 'when_to_prefer_alternative': 'clusterProfiler when needing multiple pathway databases (KEGG, GO, Reactome) or more flexible organism support', 'evidence_url': 'needs_verification', 'search_query': 'clusterProfiler vs ReactomePA pathway enrichment comparison'}
- {'tool': 'KEGG pathway analysis tools', 'when_to_prefer_this': 'ReactomePA when requiring curated, peer-reviewed Reactome pathways with detailed mechanistic annotations', 'when_to_prefer_alternative': 'KEGG tools when needing broader organism coverage or KEGG-specific pathway knowledge', 'evidence_url': 'needs_verification', 'search_query': 'Reactome vs KEGG pathway database comparison bioinformatics'}
- {'tool': 'Enrichr', 'when_to_prefer_this': 'ReactomePA when requiring programmatic analysis and integration into automated workflows', 'when_to_prefer_alternative': 'Enrichr when needing interactive web interface and multiple library options', 'evidence_url': 'needs_verification', 'search_query': 'Enrichr vs Reactome pathway enrichment tools comparison'}

## Citations

- Yu G, He QY. (2016). ReactomePA: an R/Bioconductor package for reactome pathway analysis and visualization. Molecular BioSystems, 12(2):477-479. [PMID:26661513](https://pubmed.ncbi.nlm.nih.gov/26661513) doi:10.1039/C5MB00663E

## References

- Homepage: Not provided in documentation
- Documentation: Provided in rawText (tool documentation)
- needs_verification - ReactomePA R package publication DOI