#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mergeomics — one_step_mergeomics
// Run both Marker Set Enrichment Analysis (MSEA) and Weighted Key Driver Analysis (wKDA) in a single pipeline.
// Input: genes.txt, marker.txt, modules.txt, coexpr.info.txt, network.txt
// Container: quay.io/biocontainers/bioconductor-mergeomics:1.38.0--r45hdfd78af_0
// R packages: Mergeomics
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MERGEOMICS_ONE_STEP_MERGEOMICS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mergeomics:1.38.0--r45hdfd78af_0"

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
    .bm_deps <- c("Mergeomics")
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
    
    # Load the required library
    library(Mergeomics)
    
    # Ensure the output directory exists
    dir.create("Results", showWarnings = FALSE, recursive = TRUE)
    
    # Define pipeline parameters in a list using the declared user input files
    plan <- list()
    plan\$label <- "hdlc"
    plan\$folder <- "Results"
    plan\$genfile <- "genes.txt"
    plan\$marfile <- "marker.txt"
    plan\$modfile <- "modules.txt"
    plan\$inffile <- "coexpr.info.txt"
    plan\$netfile <- "network.txt"
    
    ## Define pipeline parameters (permutation type, permutation number, 
    ## min and max module sizes)
    plan\$permtype <- "gene" ## default setting is gene permutation
    plan\$nperm <- 100 ## default value is 20000
    plan\$mingenes <- 10   ## default value is 10
    plan\$maxgenes <- 500   ## default value is 500
    
    ## Call the one-step pipeline function including both MSEA and KDA steps
    ## Keeping all arguments exactly as documented
    plan <- MSEA.KDA.onestep(plan, apply.MSEA=TRUE, apply.KDA=TRUE, 
                             maxoverlap.genesets=0.20, symbol.transfer.needed=TRUE, 
                             sym.from=c("HUMAN", "MOUSE"), sym.to=c("HUMAN", "MOUSE"))
    
    # Save the final plan object containing the pipeline results and configurations
    saveRDS(plan, file = "Results/mergeomics_pipeline_plan.rds")
    
    # Print execution completion message
    cat("Mergeomics one-step pipeline completed successfully. Results are saved in the 'Results' directory.\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MERGEOMICS_ONE_STEP_MERGEOMICS":
        mergeomics: \$(Rscript -e 'cat(as.character(packageVersion("mergeomics")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_step_mergeomics.csv versions.yml
    """
}

workflow BIOC_MERGEOMICS_ONE_STEP_MERGEOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genes.txt, marker.txt, modules.txt, coexpr.info.txt, network.txt ] ]

    main:
    BIOC_MERGEOMICS_ONE_STEP_MERGEOMICS(ch_input)

    emit:
    tables   = BIOC_MERGEOMICS_ONE_STEP_MERGEOMICS.out.tables
    plots    = BIOC_MERGEOMICS_ONE_STEP_MERGEOMICS.out.plots
    objects  = BIOC_MERGEOMICS_ONE_STEP_MERGEOMICS.out.objects
    versions = BIOC_MERGEOMICS_ONE_STEP_MERGEOMICS.out.versions
}
