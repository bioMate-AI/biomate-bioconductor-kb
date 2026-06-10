#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Mfuzz — soft_clustering_pipeline
// Pre-process time-series omics data, estimate the optimal fuzzifier parameter, perform fuzzy c-means clustering, and visualize the resulting soft clusters.
// Input: yeast.txt, yeast
// Container: quay.io/biocontainers/bioconductor-mfuzz:2.70.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, Mfuzz
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter genes/proteins with excessive missing values using filter.NA
//  * 2. [Core Analysis] Impute remaining missing values using fill.NA
//  * 3. [Core Analysis] Filter low-variation genes using filter.std
//  * 4. [Core Analysis] Standardise expression profiles using standardise
//  * 5. [Core Analysis] Estimate the fuzzifier parameter m using mestimate
//  * 6. [Core Analysis] Run fuzzy c-means clustering using mfuzz
//  * 7. [Visualization & Output] Plot the soft clusters using mfuzz.plot

nextflow.enable.dsl = 2

process BIOC_MFUZZ_SOFT_CLUSTERING_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(Mfuzz)
    library(Biobase)
    
    # Read input files from the working directory
    yeast <- NULL
    
    if (file.exists("yeast") && !dir.exists("yeast")) {
      # Try reading as RDS
      yeast <- tryCatch({
        readRDS("yeast")
      }, error = function(e) {
        # Try loading as RData
        env <- new.env()
        tryCatch({
          load("yeast", envir = env)
          for (nm in ls(env)) {
            if (inherits(env[[nm]], "ExpressionSet")) {
              return(env[[nm]])
            }
          }
        }, error = function(e2) NULL)
        return(NULL)
      })
    }
    
    if (is.null(yeast)) {
      if (file.exists("yeast.txt")) {
        yeast <- table2eset("yeast.txt")
      } else {
        stop("Error: Neither 'yeast' (ExpressionSet file) nor 'yeast.txt' (tab-delimited text) was found in the working directory.")
      }
    }
    
    # Execute the documented workflow exactly as specified
    yeast.r <- filter.NA(yeast, thres=0.25)
    yeast.f <- fill.NA(yeast.r,mode="mean")
    tmp <- filter.std(yeast.f,min.std=0)  
    yeast.s <- standardise(tmp)
    
    m1 <- mestimate(yeast.s)
    print(m1)
    
    cl <- mfuzz(yeast.s,c=16,m=m1)
    
    # Plotting to PDF
    pdf("mfuzz_plots.pdf", width=12, height=12)
    mfuzz.plot(yeast.s,cl=cl,mfrow=c(4,4))
    dev.off()
    
    # Save meaningful results
    saveRDS(cl, "mfuzz_clustering.rds")
    saveRDS(yeast.s, "yeast_standardised.rds")
    writeLines(as.character(m1), "estimated_fuzzifier.txt")
    write.csv(cl\$membership, "cluster_membership.csv", row.names=TRUE)
    write.csv(cl\$centers, "cluster_centers.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_MFUZZ_SOFT_CLUSTERING_PIPELINE":',
        paste0('    Mfuzz: ', as.character(packageVersion('Mfuzz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_soft_clustering_pipeline.csv versions.yml
    """
}

workflow BIOC_MFUZZ_SOFT_CLUSTERING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ yeast.txt, yeast ] ]

    main:
    BIOC_MFUZZ_SOFT_CLUSTERING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_MFUZZ_SOFT_CLUSTERING_PIPELINE.out.tables
    plots    = BIOC_MFUZZ_SOFT_CLUSTERING_PIPELINE.out.plots
    objects  = BIOC_MFUZZ_SOFT_CLUSTERING_PIPELINE.out.objects
    versions = BIOC_MFUZZ_SOFT_CLUSTERING_PIPELINE.out.versions
}
