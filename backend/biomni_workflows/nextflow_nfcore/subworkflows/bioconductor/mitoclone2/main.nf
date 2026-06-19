#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mitoclone2 — variant_calling_from_bam
// Extract base counts from single-cell BAM files and call high-confidence mitochondrial variants using exclusion lists or cohort-based filtering.
// Input: cell_bams/
// Container: quay.io/biocontainers/bioconductor-mitoclone2:1.16.0--r45ha27e39d_0
// R packages: mitoClone2, pheatmap
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: cluster plot

nextflow.enable.dsl = 2

process BIOC_MITOCLONE2_VARIANT_CALLING_FROM_BAM {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mitoclone2:1.16.0--r45ha27e39d_0"

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
    .bm_deps <- c("mitoClone2", "pheatmap")
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
    library(mitoClone2)
    library(pheatmap)
    
    # --- Count nucleotides from BAM files (User Input Stage) ---
    # The pipeline reads either a multiplexed 10x BAM file or a directory of single-cell BAM files.
    if (file.exists("multiplexed_10x.bam")) {
      message("Processing multiplexed 10x Genomics BAM file...")
      example.counts <- bam2R_10x(
        file = "multiplexed_10x.bam",
        sites = "chrM:1-15000",
        ncores = 1
      )
    } else if (dir.exists("cell_bams")) {
      message("Processing single-cell BAM files from cell_bams/ directory...")
      bam_files <- list.files("cell_bams", pattern = "\\\\.bam\$", full.names = TRUE)
      if (length(bam_files) == 0) {
        stop("Error: No BAM files found in 'cell_bams/' directory.")
      }
      example.counts <- baseCountsFromBamList(
        bamfiles = bam_files,
        sites = "chrM:1-15000",
        ncores = 1
      )
    } else {
      stop("Error: Neither 'multiplexed_10x.bam' nor 'cell_bams/' directory was found in the working directory.")
    }
    
    # Save the raw base counts object
    saveRDS(example.counts, file = "baseCounts.rds")
    
    # --- Call and filter mutations using exclusion list ---
    message("Calling mutations using exclusion list...")
    Example <- mutationCallsFromExclusionlist(
      example.counts,
      min.af = 0.05,
      min.num.samples = 5,
      universal.var.cells = 0.5 * length(example.counts),
      binarize = 0.1
    )
    
    # Save exclusion list mutation calls
    saveRDS(Example, file = "Example_exclusionlist.rds")
    
    # Set up metadata
    Example.rawnames <- getAlleleCount(Example, 'nonmutant')
    Example.meta <- data.frame(
      row.names = rownames(Example.rawnames),
      Clone = gsub("_.*", "", gsub("Donor1_", "", rownames(Example.rawnames)))
    )
    write.csv(Example.meta, file = "Example_metadata.csv", row.names = TRUE)
    
    # Perform quick clustering and visualization for exclusion list results
    message("Generating clustering plot for exclusion list mutations...")
    pdf("clustered_exclusionlist.pdf", width = 8, height = 8)
    clustered <- quick_cluster(
      Example,
      binarize = TRUE,
      drop_empty = TRUE,
      clustering.method = "ward.D2",
      annotation_col = Example.meta,
      show_colnames = FALSE,
      fontsize_row = 7
    )
    dev.off()
    
    # --- Call and filter mutations using Cohort-based filtering ---
    message("Calling mutations using cohort-based filtering...")
    Example <- mutationCallsFromCohort(
      example.counts,
      MINFRAC = 0.01,
      MINCELL = 8,
      MINCELLS.PATIENT = 5,
      patient = Example.meta\$Clone,
      sites = 'chrM:1-55'
    )
    
    # Save cohort mutation calls
    saveRDS(Example, file = "Example_cohort.rds")
    
    # Extract private mutations and perform downstream matrix-based clustering
    message("Extracting private mutations...")
    private.mutations <- unique(unlist(
      lapply(
        Example[grep('^C', names(Example))][unlist(lapply(Example[grep('^C', names(Example))], function(x) !is.null(x)))],
        function(y) names(getVarsCandidate(y))
      )
    ))
    
    if (length(private.mutations) > 0) {
      message("Processing private mutations matrix...")
      private.mutations.df <- pullcountsVars(
        example.counts,
        gsub("X(\\d+)([AGCT])\\\\.([AGCT])", "\\1 \\2>\\3", private.mutations)
      )
      
      private.mutations.df <- mutationCallsFromMatrix(
        t(private.mutations.df\$M),
        t(private.mutations.df\$N),
        cluster = rep(TRUE, length(private.mutations))
      )
      
      saveRDS(private.mutations.df, file = "private_mutations_calls.rds")
      
      message("Generating clustering plot for cohort-based private mutations...")
      pdf("clustered_cohort.pdf", width = 8, height = 8)
      clustered <- quick_cluster(
        private.mutations.df,
        binarize = TRUE,
        drop_empty = TRUE,
        clustering.method = "ward.D2",
        annotation_col = Example.meta,
        show_colnames = FALSE,
        fontsize_row = 7
      )
      dev.off()
    } else {
      message("No private mutations identified for cohort-based clustering.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MITOCLONE2_VARIANT_CALLING_FROM_BAM":',
        paste0('        mitoclone2: ', as.character(packageVersion("mitoclone2")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_variant_calling_from_bam.csv versions.yml
    """
}

workflow BIOC_MITOCLONE2_VARIANT_CALLING_FROM_BAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cell_bams/ ] ]

    main:
    BIOC_MITOCLONE2_VARIANT_CALLING_FROM_BAM(ch_input)

    emit:
    tables   = BIOC_MITOCLONE2_VARIANT_CALLING_FROM_BAM.out.tables
    plots    = BIOC_MITOCLONE2_VARIANT_CALLING_FROM_BAM.out.plots
    objects  = BIOC_MITOCLONE2_VARIANT_CALLING_FROM_BAM.out.objects
    versions = BIOC_MITOCLONE2_VARIANT_CALLING_FROM_BAM.out.versions
}
