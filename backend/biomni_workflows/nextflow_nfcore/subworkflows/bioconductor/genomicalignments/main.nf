#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomicalignments — read_counting_for_differential_expression
// Count aligned reads overlapping genomic features to prepare a count matrix for downstream differential expression analysis.
// Input: bamfiles, features
// Container: quay.io/biocontainers/bioconductor-genomicalignments:1.46.0--r45h01b2380_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genomicalignments:1.46.0--r45h01b2380_0"

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
    .bm_deps <- c("DESeq2", "biocmanager", "edgeR", "genomicalignments", "genomicfeatures", "pasillabamsubset", "rsamtools")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # 1. Load GenomicAlignments and downstream analysis packages
    library(GenomicAlignments)
    library(DESeq2)
    library(edgeR)
    
    # 2. Define genomic features of interest and BAM files from user input
    if (file.exists("features.rds")) {
        features <- readRDS("features.rds")
    } else if (file.exists("features")) {
        features <- readRDS("features")
    } else {
        stop("Error: Genomic features file ('features.rds' or 'features') not found in the working directory.")
    }
    
    fls <- list.files(pattern = "\\.bam\$", full.names = TRUE)
    if (length(fls) == 0) {
        stop("Error: No BAM files (*.bam) found in the working directory.")
    }
    
    # Assign names to the file list to ensure the overlap object has valid sample names
    names(fls) <- tools::file_path_sans_ext(basename(fls))
    
    # 3. Count overlaps between reads and features using summarizeOverlaps
    olap <- summarizeOverlaps(features, fls)
    
    # 4. Convert the overlap object into a DESeqDataSet or DGEList for differential expression analysis
    deseq <- DESeqDataSet(olap, design= ~ 1)
    edger <- DGEList(assay(olap), group=rownames(colData(olap)))
    
    # 5. Save outputs to the working directory
    write.csv(assay(olap), file = "read_counts.csv", row.names = TRUE)
    saveRDS(olap, file = "summarized_overlaps.rds")
    saveRDS(deseq, file = "deseq_dataset.rds")
    saveRDS(edger, file = "edger_dgelist.rds")
    
    cat("Pipeline completed successfully. Outputs saved: read_counts.csv, summarized_overlaps.rds, deseq_dataset.rds, edger_dgelist.rds\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION":
        genomicalignments: \$(Rscript -e 'cat(as.character(packageVersion("genomicalignments")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_read_counting_for_differential_expression.csv versions.yml
    """
}

workflow BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bamfiles, features ] ]

    main:
    BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_GENOMICALIGNMENTS_READ_COUNTING_FOR_DIFFERENTIAL_EXPRESSION.out.versions
}
