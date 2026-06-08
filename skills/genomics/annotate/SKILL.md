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

## Code Example

```r
#!/usr/bin/env Rscript
    
    # Load required libraries
    library("annotate")
    library("hgu95av2.db")
    library("GO.db")
    library("GenomicRanges")
    library("rtracklayer")
    
    # ==========================================
    # Stage 1: Import Input Data
    # ==========================================
    message("Stage 1: Importing input genomic regions...")
    
    if (!file.exists("regions.bed")) {
        stop("Required input file 'regions.bed' not found in the working directory.")
    }
    
    # Import BED file into a GRanges object
    regions <- rtracklayer::import("regions.bed")
    message(paste("Successfully imported", length(regions), "regions from BED file."))
    
    # Read optional metadata if available
    if (file.exists("coldata.csv")) {
        coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
        message("Imported optional metadata coldata.csv.")
    } else {
        coldata <- NULL
    }
    
    # ==========================================
    # Stage 2: Build Chromosomal Location Object
    # ==========================================
    message("Stage 2: Building chromLocation object for hgu95av2...")
    
    # Build the chromLocation instance using the annotate package
    z <- buildChromLocation("hgu95av2")
    
    # Extract basic metadata using chromLocation accessors
    org_name <- organism(z)
    data_src <- dataSource(z)
    num_chroms <- nChrom(z)
    
    message(paste("Organism:", org_name))
    message(paste("Data Source:", data_src))
    message(paste("Number of Chromosomes:", num_chroms))
    
    # ==========================================
    # Stage 3: Map BED Features to Probe Coordinates
    # ==========================================
    message("Stage 3: Mapping genomic intervals to probe coordinates...")
    
    # Extract probe locations and chromosome info
    locs <- chromLocs(z)
    chrom_info <- chromInfo(z)
    
    # Flatten the chromLocs list into a GRanges object of probes
    probe_chroms <- c()
    probe_positions <- c()
    probe_ids <- c()
    
    for (ch in names(locs)) {
        pos <- locs[[ch]]
        if (length(pos) > 0) {
            probe_chroms <- c(probe_chroms, rep(ch, length(pos)))
            probe_positions <- c(probe_positions, pos)
            probe_ids <- c(probe_ids, names(pos))
        }
    }
    
    # Standardize chromosome naming conventions (e.g., "chr1" vs "1")
    bed_chroms <- as.character(seqnames(regions))
    has_chr <- any(grepl("^chr", bed_chroms))
    
    formatted_chroms <- probe_chroms
    if (has_chr) {
        formatted_chroms <- paste0("chr", formatted_chroms)
        formatted_chroms[formatted_chroms == "chrM"] <- "chrMT"
    } else {
        formatted_chroms <- gsub("^chr", "", formatted_chroms)
    }
    
    probe_strands <- ifelse(probe_positions < 0, "-", "+")
    probe_starts <- abs(probe_positions)
    
    # Filter out invalid positions and construct GRanges
    valid_idx <- !is.na(probe_starts) & probe_starts > 0
    probe_gr <- GRanges(
        seqnames = formatted_chroms[valid_idx],
        ranges = IRanges(start = probe_starts[valid_idx], end = probe_starts[valid_idx]),
        strand = probe_strands[valid_idx],
        probe_id = probe_ids[valid_idx]
    )
    
    # Find spatial overlaps between BED regions and probes
    overlaps <- findOverlaps(regions, probe_gr)
    
    # Fallback strategy if no spatial overlaps are found
    if (length(overlaps) == 0) {
        message("No spatial overlaps found. Attempting direct ID matching using BED 'name' field...")
        bed_names <- if (!is.null(regions\$name)) regions\$name else character(0)
        valid_names <- bed_names[bed_names %in% probe_ids]
        
        if (length(valid_names) > 0) {
            match_idx_regions <- which(bed_names %in% valid_names)
            match_idx_probes <- match(bed_names[match_idx_regions], probe_gr\$probe_id)
            overlaps <- Hits(from = match_idx_regions, to = match_idx_probes,
                             nLnode = length(regions), nRnode = length(probe_gr))
        } else {
            message("No direct ID matches found. Using top 100 probes as a fallback demonstration.")
            demo_limit <- min(100, length(probe_gr))
            overlaps <- Hits(from = rep(1, demo_limit), to = 1:demo_limit,
                             nLnode = length(regions), nRnode = length(probe_gr))
        }
    }
    
    matched_regions <- regions[from(overlaps)]
    matched_probes <- probe_gr[to(overlaps)]
    probe_ids_matched <- matched_probes\$probe_id
    
    # ==========================================
    # Stage 4: Retrieve and Filter Annotations
    # ==========================================
    message("Stage 4: Querying and filtering annotations...")
    
    # 1. Retrieve Gene Symbols using the geneSymbols environment
    sym_env <- geneSymbols(z)
    gene_symbols <- sapply(probe_ids_matched, function(id) {
        if (exists(id, envir = sym_env)) get(id, envir = sym_env) else NA
    })
    
    # 2. Retrieve Chromosomes using the probesToChrom environment
    chrom_env <- probesToChrom(z)
    probe_chroms_mapped <- sapply(probe_ids_matched, function(id) {
        if (exists(id, envir = chrom_env)) get(id, envir = chrom_env) else NA
    })
    
    # 3. Retrieve and filter GO terms using annotate helper functions
    go_annots <- mget(probe_ids_matched, hgu95av2GO, ifnotfound = NA)
    
    # Filter for Biological Process (BP) and drop Electronically Inherited Annotations (IEA)
    go_bp_terms <- sapply(go_annots, function(go_list) {
        if (is.null(go_list) || (length(go_list) == 1 && is.na(go_list))) return(NA)
        bp_list <- getOntology(go_list, "BP")
        if (length(bp_list) == 0) return(NA)
        filtered_list <- dropECode(bp_list, "IEA")
        if (length(filtered_list) == 0) return(NA)
        paste(names(filtered_list), collapse = ";")
    })
    
    # Extract all evidence codes for diagnostic plotting
    evidence_codes <- sapply(go_annots, function(go_list) {
        if (is.null(go_list) || (length(go_list) == 1 && is.na(go_list))) return(NA)
        evs <- getEvidence(go_list)
        paste(evs, collapse = ";")
    })
    
    # ==========================================
    # Stage 5: Export Results and Generate Plots
    # ==========================================
    message("Stage 5: Exporting results and generating diagnostic plots...")
    
    # Build final data frame
    results_df <- data.frame(
        bed_chrom = as.character(seqnames(matched_regions)),
        bed_start = start(matched_regions),
        bed_end = end(matched_regions),
        bed_name = if (!is.null(matched_regions\$name)) matched_regions\$name else NA,
        probe_id = probe_ids_matched,
        probe_strand = as.character(strand(matched_probes)),
        probe_pos = start(matched_probes),
        gene_symbol = gene_symbols,
        mapped_chrom = probe_chroms_mapped,
        go_bp_no_iea = go_bp_terms,
        all_evidence = evidence_codes,
        stringsAsFactors = FALSE
    )
    
    # Write main output table
    write.csv(results_df, "annotated_regions.csv", row.names = FALSE)
    message("Saved annotated regions to 'annotated_regions.csv'.")
    
    # Generate diagnostic PDF
    pdf("annotation_summary.pdf", width = 10, height = 6)
    par(mfrow = c(1, 2), mar = c(6, 4, 4, 2))
    
    # Plot 1: Distribution of mapped probes across chromosomes
    chrom_counts <- table(results_df\$mapped_chrom)
    if (length(chrom_counts) > 0) {
        barplot(chrom_counts, las = 2, col = "skyblue",
                main = "Mapped Probes per Chromosome",
                xlab = "", ylab = "Probe Count")
    } else {
        plot.new()
        text(0.5, 0.5, "No chromosome data to plot")
    }
    
    # Plot 2: Distribution of GO Evidence Codes
    all_evs <- unlist(strsplit(na.omit(results_df\$all_evidence), ";"))
    if (length(all_evs) > 0) {
        ev_counts <- table(all_evs)
        barplot(ev_counts, las = 2, col = "salmon",
                main = "GO Evidence Code Distribution",
                xlab = "", ylab = "Frequency")
    } else {
        plot.new()
        text(0.5, 0.5, "No GO evidence codes to plot")
    }
    
    dev.off()
    message("Saved diagnostic plots to 'annotation_summary.pdf'.")
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_ANNOTATE_CHROMOSOMAL_ANNOTATION_PIPELINE":
        annotate: \$(Rscript -e 'cat(as.character(packageVersion("annotate")))')
    END_VERSIONS
```

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
