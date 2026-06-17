#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RiboDiPA — exon_level_analysis
// Perform differential pattern analysis using exons as the bins, suitable for higher organisms with alternative splicing.
// Input: bam_path[1:4], bam_path[5]
// Container: quay.io/biocontainers/bioconductor-ribodipa:1.18.0--r45ha27e39d_0
// R packages: RiboDiPA
// Bioconductor: 3.20 | R: 4.4
// Requires: RiboDiPA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Map ribosome protected fragments to P-sites using psiteMapping()
//  * 2. [Core Analysis] Perform exon-level binning and differential pattern testing using diffPatternTestExon()

nextflow.enable.dsl = 2

process BIOC_RIBODIPA_EXON_LEVEL_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("RiboDiPA")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(RiboDiPA)
    
    # -----------------------------------------------------------------------------
    # 1. Retrieve User Input Files from Working Directory
    # -----------------------------------------------------------------------------
    # Find BAM files and GTF file in the current working directory
    bam_files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    gtf_files <- list.files(pattern = "\\\\.gtf\$", full.names = TRUE)
    
    if (length(bam_files) < 4) {
        stop("Error: At least 4 BAM files are required in the working directory.")
    }
    if (length(gtf_files) < 1) {
        stop("Error: At least 1 GTF file is required in the working directory.")
    }
    
    # Construct the bam_path vector as specified:
    # bam_path[1:4] are the BAM files, bam_path[5] is the GTF file
    bam_path <- c(bam_files[1:4], gtf_files[1])
    
    # -----------------------------------------------------------------------------
    # 2. Define Experimental Design (Class Label)
    # -----------------------------------------------------------------------------
    # Define the comparison conditions: '1' for control, '2' for treatment
    classlabel <- data.frame(
        condition = c("treatment", "treatment", "control", "control"),
        comparison = c(2, 2, 1, 1)
    )
    # Use the basenames of the BAM files (without extension) as rownames to ensure matching
    rownames(classlabel) <- gsub("\\\\.bam\$", "", basename(bam_path[1:4]))
    
    # -----------------------------------------------------------------------------
    # 3. Execute RiboDiPA Exon-Level Workflow
    # -----------------------------------------------------------------------------
    # Stage 1: Map ribosome protected fragments to P-sites
    data.psite <- psiteMapping(bam_file_list = bam_path[1:4], 
        gtf_file = bam_path[5], psite.mapping = "auto", cores = 2)
    
    # Stage 2: Perform exon-level binning and differential pattern testing
    result.exon <- diffPatternTestExon(psitemap = data.psite,
        classlabel = classlabel, method = c('gtxr', 'qvalue'))
    
    # -----------------------------------------------------------------------------
    # 4. Save Outputs and Generate Plots
    # -----------------------------------------------------------------------------
    # Save RDS objects of the intermediate and final results
    saveRDS(data.psite, "exon_level_psite_mapping.rds")
    saveRDS(result.exon, "exon_level_analysis_results.rds")
    
    # Save gene-level differential pattern testing results to CSV
    if (!is.null(result.exon\$gene)) {
        write.csv(result.exon\$gene, "exon_level_gene_results.csv", row.names = TRUE)
        
        # Generate track plots for the top significant genes if available
        significant_genes <- rownames(result.exon\$gene)[order(result.exon\$gene\$qvalue)]
        if (length(significant_genes) > 0) {
            top_genes <- significant_genes[1:min(2, length(significant_genes))]
            
            pdf("exon_level_track_plots.pdf", width = 8, height = 6)
            tryCatch({
                plotTrack(data = data.psite, genes.list = top_genes, replicates = NULL, exons = TRUE)
            }, error = function(e) {
                warning("Could not generate track plots: ", e\$message)
            })
            dev.off()
        }
    }
    
    # Generate binned ribosome track plots for significant genes
    pdf("exon_level_differential_pattern_plots.pdf", width = 10, height = 8)
    tryCatch({
        plotTest(result = result.exon, genes.list = NULL, threshold = 0.05)
    }, error = function(e) {
        warning("Could not generate differential pattern plots: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_RIBODIPA_EXON_LEVEL_ANALYSIS":',
        paste0('    RiboDiPA: ', as.character(packageVersion('RiboDiPA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_exon_level_analysis.csv versions.yml
    """
}

workflow BIOC_RIBODIPA_EXON_LEVEL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_path[1:4], bam_path[5] ] ]

    main:
    BIOC_RIBODIPA_EXON_LEVEL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RIBODIPA_EXON_LEVEL_ANALYSIS.out.tables
    plots    = BIOC_RIBODIPA_EXON_LEVEL_ANALYSIS.out.plots
    objects  = BIOC_RIBODIPA_EXON_LEVEL_ANALYSIS.out.objects
    versions = BIOC_RIBODIPA_EXON_LEVEL_ANALYSIS.out.versions
}
