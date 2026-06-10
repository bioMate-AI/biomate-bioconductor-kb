#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: metaseqr2 — rna_seq_pipeline
// Run the complete metaseqr2 pipeline starting from a count matrix with embedded annotations to perform normalization, statistical testing, filtering, and HTML re
// Input: mm9GeneCounts, sampleListMm9, libsizeListMm9
// Container: quay.io/biocontainers/bioconductor-metaseqr2:1.22.0--r45h01b2380_0
// R packages: metaseqR2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METASEQR2_RNA_SEQ_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-metaseqr2:1.22.0--r45h01b2380_0"

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
    .bm_deps <- c("metaseqR2")
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
    
    # 1. Set random seed for reproducible downsampling in plots
    set.seed(42)
    
    # Load required library
    library(metaseqR2)
    
    # Read user inputs from the working directory
    mm9GeneCounts <- readRDS("mm9GeneCounts.rds")
    sampleListMm9 <- readRDS("sampleListMm9.rds")
    libsizeListMm9 <- readRDS("libsizeListMm9.rds")
    
    # 2. Run the main pipeline function metaseqr2 with specified normalization, 
    # statistical algorithms, filtering, and output directory.
    result <- metaseqr2(
        counts=mm9GeneCounts,
        sampleList=sampleListMm9,
        contrast=c("adult_8_weeks_vs_e14.5"),
        libsizeList=libsizeListMm9,
        annotation="embedded",
        embedCols=list(
            idCol=4,
            gcCol=5,
            nameCol=8,
            btCol=7
        ),
        org="mm9",
        countType="gene",
        normalization="edger",
        statistics="edger",
        pcut=0.05,
        qcPlots=c(
            "mds","filtered","correl","pairwise","boxplot","gcbias",
            "lengthbias","meandiff","meanvar","deheatmap","volcano",
            "mastat"
        ),
        figFormat=c("png","pdf"),
        exportWhat=c("annotation","p_value","adj_p_value","fold_change"),
        exportScale=c("natural","log2"),
        exportValues="normalized",
        exportStats=c("mean","sd","cv"),
        exportWhere=file.path(tempdir(),"test1"),
        restrictCores=0.01,
        geneFilters=list(
             length=list(
                    length=500
             ),
             avgReads=list(
                    averagePerBp=100,
                    quantile=0.25
             ),
             expression=list(
                    median=TRUE,
                    mean=FALSE,
                    quantile=NA,
                    known=NA,
                    custom=NA
             ),
             biotype=getDefaults("biotypeFilter","mm9")
        ),
        outList=TRUE
    )
    
    # 3. Inspect the resulting differential expression data
    de_results <- result[["data"]][["adult_8_weeks_vs_e14.5"]]
    print(head(de_results))
    
    # 4. Write named output files for the meaningful results
    # Save the complete result object
    saveRDS(result, "metaseqr2_pipeline_result.rds")
    
    # Save the differential expression table as a CSV file
    write.csv(de_results, "differential_expression_adult_8_weeks_vs_e14.5.csv", row.names=TRUE)
    
    # Copy the generated HTML report and plots from the temporary directory to the working directory
    temp_out_dir <- file.path(tempdir(), "test1")
    if (dir.exists(temp_out_dir)) {
        file.copy(from=temp_out_dir, to=".", recursive=TRUE)
        message("Pipeline execution complete. Results and HTML report copied to the working directory under './test1/'")
    } else {
        message("Pipeline execution complete, but temporary output directory was not found.")
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_METASEQR2_RNA_SEQ_PIPELINE":
        metaseqr2: \$(Rscript -e 'cat(as.character(packageVersion("metaseqr2")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_pipeline.csv versions.yml
    """
}

workflow BIOC_METASEQR2_RNA_SEQ_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mm9GeneCounts, sampleListMm9, libsizeListMm9 ] ]

    main:
    BIOC_METASEQR2_RNA_SEQ_PIPELINE(ch_input)

    emit:
    tables   = BIOC_METASEQR2_RNA_SEQ_PIPELINE.out.tables
    plots    = BIOC_METASEQR2_RNA_SEQ_PIPELINE.out.plots
    objects  = BIOC_METASEQR2_RNA_SEQ_PIPELINE.out.objects
    versions = BIOC_METASEQR2_RNA_SEQ_PIPELINE.out.versions
}
