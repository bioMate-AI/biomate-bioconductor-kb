#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribodipa — ribodipa_wrapper_pipeline
// Run the entire RiboDiPA pipeline using the single wrapper function with default parameters.
// Input: bam_path[1:4], bam_path[5]
// Container: quay.io/biocontainers/bioconductor-ribodipa:1.18.0--r45ha27e39d_0
// R packages: RiboDiPA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBODIPA_RIBODIPA_WRAPPER_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ribodipa:1.18.0--r45ha27e39d_0"

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
    
    # Load required library
    library(RiboDiPA)
    
    # 1. Define experimental design and comparison groups
    # Locate the user input files in the working directory
    bam_files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    gtf_files <- list.files(pattern = "\\\\.gtf\$", full.names = TRUE)
    
    if (length(bam_files) < 4) {
        stop("Error: At least 4 BAM files are required in the working directory.")
    }
    if (length(gtf_files) < 1) {
        stop("Error: At least 1 GTF file is required in the working directory.")
    }
    
    # Construct the bam_path vector as specified: bam_path[1:4] are BAMs, bam_path[5] is GTF
    bam_path <- c(bam_files[1:4], gtf_files[1])
    
    # Define the experimental design and comparison groups
    classlabel <- data.frame(
        condition = c("mutant", "mutant", "wildtype", "wildtype"),
        comparison = c(2, 2, 1, 1)
    )
    rownames(classlabel) <- c("mutant1","mutant2","wildtype1","wildtype2")
    
    # 2. Run the wrapper function to map P-sites, bin data, and perform differential testing
    result.wrp <- RiboDiPA(bam_path[1:4], bam_path[5], classlabel, cores = 2)
    
    # 3. View significant gene results
    head(result.wrp\$gene[order(result.wrp\$gene\$qvalue), ])
    
    # 4. Write named output files for the meaningful results
    # Save the complete RiboDiPA result object
    saveRDS(result.wrp, file = "ribodipa_results.rds")
    
    # Save the gene-level results table
    write.csv(result.wrp\$gene, file = "ribodipa_gene_results.csv", row.names = TRUE)
    
    # Save the bin-level results table if available
    if (!is.null(result.wrp\$bin)) {
        write.csv(result.wrp\$bin, file = "ribodipa_bin_results.csv", row.names = TRUE)
    }
    
    # Generate and save visualization plots
    pdf("ribodipa_plots.pdf", width = 10, height = 8)
    
    # Plot ribosome per nucleotide tracks of top significant genes
    top_genes <- rownames(result.wrp\$gene[order(result.wrp\$gene\$qvalue), ])[1:2]
    top_genes <- top_genes[!is.na(top_genes)]
    
    if (length(top_genes) > 0 && !is.null(result.wrp\$data.psite)) {
        tryCatch({
            plotTrack(data = result.wrp\$data.psite, genes.list = top_genes, replicates = NULL, exons = FALSE)
        }, error = function(e) {
            message("Could not generate track plot: ", e\$message)
        })
    }
    
    # Plot binned ribosome tracks of significant genes
    tryCatch({
        plotTest(result = result.wrp, genes.list = NULL, threshold = 0.05)
    }, error = function(e) {
        message("Could not generate test plot: ", e\$message)
    })
    
    dev.off()

    writeLines(c(
        '"BIOC_RIBODIPA_RIBODIPA_WRAPPER_PIPELINE":',
        paste0('        ribodipa: ', as.character(packageVersion("ribodipa")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ribodipa_wrapper_pipeline.csv versions.yml
    """
}

workflow BIOC_RIBODIPA_RIBODIPA_WRAPPER_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_path[1:4], bam_path[5] ] ]

    main:
    BIOC_RIBODIPA_RIBODIPA_WRAPPER_PIPELINE(ch_input)

    emit:
    tables   = BIOC_RIBODIPA_RIBODIPA_WRAPPER_PIPELINE.out.tables
    plots    = BIOC_RIBODIPA_RIBODIPA_WRAPPER_PIPELINE.out.plots
    objects  = BIOC_RIBODIPA_RIBODIPA_WRAPPER_PIPELINE.out.objects
    versions = BIOC_RIBODIPA_RIBODIPA_WRAPPER_PIPELINE.out.versions
}
