#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipenrich — proximity_to_regulatory_regions
// Test if genomic regions tend to be closer to or farther from transcription start sites or enhancer regions in each gene set.
// Input: peaks_E2F4, vignette_genesets.txt
// Container: quay.io/biocontainers/bioconductor-chipenrich:2.34.0--r45hdfd78af_0
// Requires: chipenrich
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the path to the gene sets file. 2. Run proximity to regulatory regions test using proxReg(). 3. Extract and print the resul

nextflow.enable.dsl = 2

process BIOC_CHIPENRICH_PROXIMITY_TO_REGULATORY_REGIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
    .bm_deps <- c("chipenrich")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required library
    library(chipenrich)
    
    # 1. Define the path to the gene sets file and verify its existence
    gs_path = "vignette_genesets.txt"
    if (!file.exists(gs_path)) {
      stop("Required input file 'vignette_genesets.txt' not found in the working directory.")
    }
    
    # 2. Locate the peaks_E2F4 input file
    peaks_files = list.files(pattern = "^peaks_E2F4")
    if (length(peaks_files) == 0) {
      stop("Required input file 'peaks_E2F4' (with or without extension) not found in the working directory.")
    }
    peaks_file = peaks_files[1]
    
    # 3. Run proximity to regulatory regions test using proxReg()
    results.prox = proxReg(peaks_file, reglocation = 'tss',	genome = 'hg19', genesets=gs_path, out_name=NULL)
    
    # 4. Extract and print the results
    results.prox = results.prox\$results
    print(results.prox[1:5,1:7])
    
    # 5. Write named output files for the meaningful results
    write.csv(results.prox, "proximity_results.csv", row.names = FALSE)
    saveRDS(results.prox, "proximity_results.rds")
    
    # 6. Generate and save QC plot
    tryCatch({
      pdf("peak_dist_to_tss.pdf", width = 6, height = 6)
      plot_dist_to_tss(peaks = peaks_file, genome = 'hg19')
      dev.off()
    }, error = function(e) {
      warning("Could not generate QC plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_CHIPENRICH_PROXIMITY_TO_REGULATORY_REGIONS":',
        paste0('    chipenrich: ', as.character(packageVersion('chipenrich')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proximity_to_regulatory_regions.csv versions.yml
    """
}

workflow BIOC_CHIPENRICH_PROXIMITY_TO_REGULATORY_REGIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peaks_E2F4, vignette_genesets.txt ] ]

    main:
    BIOC_CHIPENRICH_PROXIMITY_TO_REGULATORY_REGIONS(ch_input)

    emit:
    tables   = BIOC_CHIPENRICH_PROXIMITY_TO_REGULATORY_REGIONS.out.tables
    plots    = BIOC_CHIPENRICH_PROXIMITY_TO_REGULATORY_REGIONS.out.plots
    objects  = BIOC_CHIPENRICH_PROXIMITY_TO_REGULATORY_REGIONS.out.objects
    versions = BIOC_CHIPENRICH_PROXIMITY_TO_REGULATORY_REGIONS.out.versions
}
