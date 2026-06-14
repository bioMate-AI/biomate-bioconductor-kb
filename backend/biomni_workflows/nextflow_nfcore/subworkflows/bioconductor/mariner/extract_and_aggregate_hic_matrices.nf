#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mariner — extract_and_aggregate_hic_matrices
// Extract submatrices around chromatin loops from .hic files, aggregate them across interactions or files, and plot the aggregated matrix.
// Input: FS_5kbLoops.txt, WT_5kbLoops.txt, LEUK_HEK_PJA27_inter_30.hic, LEUK_HEK_PJA30_inter_30.hic
// Container: quay.io/biocontainers/bioconductor-mariner:1.10.2--r45hdfd78af_0
// R packages: GenomeInfoDb, InteractionSet, mariner
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_MARINER_EXTRACT_AND_AGGREGATE_HIC_MATRICES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mariner:1.10.2--r45hdfd78af_0"

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
    .bm_deps <- c("GenomeInfoDb", "InteractionSet", "mariner")
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
    
    library(mariner)
    library(GenomeInfoDb)
    library(InteractionSet)
    
    ## 1. Read and merge loops from local BEDPE files
    bedpeFiles <- c(
        "FS_5kbLoops.txt",
        "WT_5kbLoops.txt"
    )
    names(bedpeFiles) <- c("FS", "WT")
    
    ## Read as list of GInteractions
    giList <-
        lapply(bedpeFiles, read.table, header=TRUE) |>
        lapply(as_ginteractions)
    
    ## Merge
    mgi <- mergePairs(x=giList, radius=10e3, column="APScoreAvg")
    
    summary(mgi)
    
    ## Define local .hic files
    hicFiles <- c(
        "LEUK_HEK_PJA27_inter_30.hic",
        "LEUK_HEK_PJA30_inter_30.hic"
    )
    names(hicFiles) <- c("FS", "WT")
    hicFiles
    
    ## 2. Match chromosome naming styles to the .hic files
    GenomeInfoDb::seqlevelsStyle(mgi) <- 'ENSEMBL'
    
    ## 3. Assign loops to bins
    binned <- assignToBins(x=mgi, binSize=100e3)
    
    ## 4. Define submatrix regions with a buffer using pixelsToMatrices()
    regions <- pixelsToMatrices(x=binned[1:1000], buffer=1)
    
    ## 5. Pull contact matrices using pullHicMatrices()
    iarr <- pullHicMatrices(
        x=regions,
        files=hicFiles,
        binSize=100e3
    )
    
    ## See count matrices
    counts(iarr)
    
    ## 6. Aggregate matrices using aggHicMatrices()
    mat <- aggHicMatrices(x=iarr)
    
    ## 7. Plot the aggregated matrix using plotMatrix() and save outputs
    pdf("aggregated_matrix_plot.pdf")
    plotMatrix(data=mat)
    dev.off()
    
    ## Save meaningful results to disk
    saveRDS(mgi, "merged_interactions.rds")
    saveRDS(mat, "aggregated_matrix.rds")
    
    ## Export merged interactions as a CSV table
    mgi_df <- as.data.frame(mgi)
    write.csv(mgi_df, "merged_interactions.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_MARINER_EXTRACT_AND_AGGREGATE_HIC_MATRICES":',
        paste0('        mariner: ', as.character(packageVersion("mariner")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_extract_and_aggregate_hic_matrices.csv versions.yml
    """
}

workflow BIOC_MARINER_EXTRACT_AND_AGGREGATE_HIC_MATRICES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ FS_5kbLoops.txt, WT_5kbLoops.txt, LEUK_HEK_PJA27_inter_30.hic, LEUK_HEK_PJA30_inter_30.hic ] ]

    main:
    BIOC_MARINER_EXTRACT_AND_AGGREGATE_HIC_MATRICES(ch_input)

    emit:
    tables   = BIOC_MARINER_EXTRACT_AND_AGGREGATE_HIC_MATRICES.out.tables
    plots    = BIOC_MARINER_EXTRACT_AND_AGGREGATE_HIC_MATRICES.out.plots
    objects  = BIOC_MARINER_EXTRACT_AND_AGGREGATE_HIC_MATRICES.out.objects
    versions = BIOC_MARINER_EXTRACT_AND_AGGREGATE_HIC_MATRICES.out.versions
}
