#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: hmmcopy — matched_tumour_normal_correction
// Normalize a tumour copy number profile against a matched normal profile to eliminate germline CNVs and reduce noise, followed by segmentation.
// Input: tumour.wig, normal.wig, gc.wig, map.wig
// Container: quay.io/biocontainers/bioconductor-hmmcopy:1.52.0--r45h01b2380_0
// R packages: HMMcopy
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HMMCOPY_MATCHED_TUMOUR_NORMAL_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-hmmcopy:1.52.0--r45h01b2380_0"

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
    .bm_deps <- c("HMMcopy")
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
    
    # Set options and load required library
    options(stringsAsFactors = TRUE)
    library(HMMcopy)
    
    # Define input file paths in the working directory
    rfile <- "normal.wig"
    gfile <- "gc.wig"
    mfile <- "map.wig"
    tfile <- "tumour.wig"
    
    # Verify that all required input files exist
    required_files <- c(rfile, gfile, mfile, tfile)
    for (f in required_files) {
      if (!file.exists(f)) {
        stop(paste("Error: Required input file '", f, "' not found in the working directory.", sep = ""))
      }
    }
    
    # 1. Load and correct normal read counts
    normal_reads <- wigsToRangedData(rfile, gfile, mfile)
    normal_copy <- correctReadcount(normal_reads)
    
    # 2. Load and correct tumour read counts
    tumour_copy <- correctReadcount(wigsToRangedData(tfile, gfile, mfile))
    
    # 3. Subtract normal copy number from tumour copy number in log space to obtain somatic copy number
    somatic_copy <- tumour_copy
    somatic_copy\$copy <- tumour_copy\$copy - normal_copy\$copy
    
    # 4. Retrieve and adjust HMM parameters to prevent convergence
    default_param <- HMMsegment(tumour_copy, getparam = TRUE)
    longseg_param <- default_param
    longseg_param\$e <- 0.999999999999999
    longseg_param\$strength <- 1e30
    newmu_param <- longseg_param
    newmu_param\$mu <- c(-0.5, -0.4, -0.15, 0.1, 0.4, 0.7)
    newmu_param\$m <- newmu_param\$mu
    
    # 5. Segment the somatic copy number profile using HMMsegment
    somatic_segments <- HMMsegment(somatic_copy, newmu_param, verbose = FALSE)
    
    # 6. Visualize the somatic segments using plotSegments and save to PDF
    pdf("somatic_segments_plot.pdf", width = 10, height = 6)
    plotSegments(somatic_copy, somatic_segments, pch = ".", ylab = "Tumour Copy Number", xlab = "Chromosome Position")
    dev.off()
    
    # Save meaningful results to output files
    # Save the somatic copy number profile as a CSV table
    write.csv(as.data.frame(somatic_copy), "somatic_copy.csv", row.names = FALSE)
    
    # Save the complete somatic segments list object as an RDS file
    saveRDS(somatic_segments, "somatic_segments.rds")
    
    # Save the segments table as a CSV file if it exists in the output list
    if (!is.null(somatic_segments\$segs)) {
      write.csv(somatic_segments\$segs, "somatic_segments.csv", row.names = FALSE)
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_HMMCOPY_MATCHED_TUMOUR_NORMAL_CORRECTION":
        hmmcopy: \$(Rscript -e 'cat(as.character(packageVersion("hmmcopy")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matched_tumour_normal_correction.csv versions.yml
    """
}

workflow BIOC_HMMCOPY_MATCHED_TUMOUR_NORMAL_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tumour.wig, normal.wig, gc.wig, map.wig ] ]

    main:
    BIOC_HMMCOPY_MATCHED_TUMOUR_NORMAL_CORRECTION(ch_input)

    emit:
    tables   = BIOC_HMMCOPY_MATCHED_TUMOUR_NORMAL_CORRECTION.out.tables
    plots    = BIOC_HMMCOPY_MATCHED_TUMOUR_NORMAL_CORRECTION.out.plots
    objects  = BIOC_HMMCOPY_MATCHED_TUMOUR_NORMAL_CORRECTION.out.objects
    versions = BIOC_HMMCOPY_MATCHED_TUMOUR_NORMAL_CORRECTION.out.versions
}
