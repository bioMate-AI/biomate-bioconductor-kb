#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scRepertoire — tcr_repertoire_analysis
// Process raw TCR contig data, combine them into clones, and perform basic and advanced repertoire visualizations and diversity analyses without single-cell expre
// Input: filtered_contig_annotations.csv
// Container: quay.io/biocontainers/bioconductor-screpertoire:2.2.0--r44he5774e6_0
// R packages: BiocStyle, circlize, ggplot2, ggraph, scales, scater, scRepertoire
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, scRepertoire
// Visualizations: scatter plot, diversity plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load contigs using loadContigs() or manual list creation. 2. Combine contigs into TCR clones using combineTCR(). 3. Add metadata v

nextflow.enable.dsl = 2

process BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BiocStyle", "circlize", "ggplot2", "ggraph", "scales", "scater", "scRepertoire")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
                    
        # Load required libraries
        library(scRepertoire)
        library(ggplot2)
        
        # 1. Load contigs from the declared user input file
        raw_contigs <- read.csv("filtered_contig_annotations.csv", stringsAsFactors = FALSE)
        
        # Treat the input file as a single sample rather than splitting by barcode suffix
        contig_list <- list(raw_contigs)
        
        # Use loadContigs to support multiple formats (10x, TRUST4, WAT3R, etc.)
        contig_list <- loadContigs(input = contig_list, format = "auto")
        
        sample_names <- paste0("Sample", seq_along(contig_list))
        
        # 2. Combine contigs into TCR clones
        combined.TCR <- combineTCR(contig_list, 
                                   samples = sample_names,
                                   removeNA = FALSE, 
                                   removeMulti = FALSE, 
                                   filterMulti = FALSE)
        
        # 3. Add metadata variables
        # Assign "B" and "L" types based on the number of actual samples recovered
        types <- rep(c("B", "L"), length.out = length(combined.TCR))
        combined.TCR <- addVariable(combined.TCR, 
                                    variable.name = "Type", 
                                    variables = types)
        
        # Save the processed combined TCR object
        saveRDS(combined.TCR, file = "combined_TCR.rds")
        
        # 4. Quantify and visualize clones
        p_quant <- clonalQuant(combined.TCR, 
                               cloneCall="strict", 
                               chain = "both", 
                               scale = TRUE)
        ggsave("clonal_quantification.pdf", plot = p_quant, width = 8, height = 6)
        
        p_abundance <- clonalAbundance(combined.TCR, 
                                       cloneCall = "gene", 
                                       scale = FALSE)
        ggsave("clonal_abundance.pdf", plot = p_abundance, width = 8, height = 6)
        
        p_length <- clonalLength(combined.TCR, 
                                cloneCall="aa", 
                                chain = "both") 
        ggsave("clonal_length.pdf", plot = p_length, width = 8, height = 6)
        
        # Safely select samples for comparative plots
        if (length(combined.TCR) > 1) {
          s1 <- names(combined.TCR)[1]
          s2 <- names(combined.TCR)[2]
          
          p_compare <- clonalCompare(combined.TCR, 
                                       top.clones = 10, 
                                       samples = c(s1, s2), 
                                       cloneCall="aa", 
                                       graph = "alluvial")
          ggsave("clonal_compare.pdf", plot = p_compare, width = 8, height = 6)
          
          p_scatter <- clonalScatter(combined.TCR, 
                                   cloneCall ="gene", 
                                   x.axis = s1, 
                                   y.axis = s2,
                                   dot.size = "total",
                                   graph = "proportion")
          ggsave("clonal_scatter.pdf", plot = p_scatter, width = 8, height = 6)
        }
        
        # 5. Analyze clonal dynamics
        p_home <- clonalHomeostasis(combined.TCR, cloneCall = "gene")
        ggsave("clonal_homeostasis.pdf", plot = p_home, width = 8, height = 6)
        
        p_prop <- clonalProportion(combined.TCR, cloneCall = "gene")
        ggsave("clonal_proportion.pdf", plot = p_prop, width = 8, height = 6)
        
        # 6. Summarize repertoires (Gene usage)
        p_genes <- percentGenes(combined.TCR, chain = "TRB", gene = "Vgene", summary.fun = "percent")
        ggsave("percent_genes.pdf", plot = p_genes, width = 8, height = 6)
        
        p_vj <- percentVJ(combined.TCR, chain = "TRB", summary.fun = "percent")
        ggsave("percent_vj.pdf", plot = p_vj, width = 8, height = 6)
        
        p_aa <- percentAA(combined.TCR, chain = "TRB", aa.length = 20)
        ggsave("percent_aa.pdf", plot = p_aa, width = 8, height = 6)
        
        p_pe <- positionalEntropy(combined.TCR, chain = "TRB", aa.length = 20)
        ggsave("positional_entropy.pdf", plot = p_pe, width = 8, height = 6)
        
        p_pp <- positionalProperty(combined.TCR, chain = "TRB", aa.length = 20, method = "atchleyFactors")
        ggsave("positional_property.pdf", plot = p_pp, width = 8, height = 6)
        
        p_kmer <- percentKmer(combined.TCR, cloneCall = "aa", chain = "TRB", motif.length = 3, top.motifs = 25)
        ggsave("percent_kmer.pdf", plot = p_kmer, width = 8, height = 6)
        
        # 7. Comparing Clonal Diversity and Overlap
        p_div <- clonalDiversity(combined.TCR, cloneCall = "gene")
        ggsave("clonal_diversity.pdf", plot = p_div, width = 8, height = 6)
        
        p_rarefaction <- clonalRarefaction(combined.TCR, cloneCall = "gene")
        ggsave("clonal_rarefaction.pdf", plot = p_rarefaction, width = 8, height = 6)
        
        p_size_dist <- clonalSizeDistribution(combined.TCR, cloneCall = "gene")
        ggsave("clonal_size_distribution.pdf", plot = p_size_dist, width = 8, height = 6)
        
        if (length(combined.TCR) > 1) {
          p_overlap <- clonalOverlap(combined.TCR, cloneCall = "gene")
          ggsave("clonal_overlap.pdf", plot = p_overlap, width = 8, height = 6)
        }

    writeLines(c(
        '"BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS":',
        paste0('    scRepertoire: ', as.character(packageVersion('scRepertoire')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tcr_repertoire_analysis.csv versions.yml
    """
}

workflow BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ filtered_contig_annotations.csv ] ]

    main:
    BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS.out.tables
    plots    = BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS.out.plots
    objects  = BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS.out.objects
    versions = BIOC_SCREPERTOIRE_TCR_REPERTOIRE_ANALYSIS.out.versions
}
