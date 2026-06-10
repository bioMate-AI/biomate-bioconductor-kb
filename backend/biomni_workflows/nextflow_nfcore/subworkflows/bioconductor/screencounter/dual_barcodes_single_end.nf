#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: screencounter — dual_barcodes_single_end
// Quantify dual barcodes where both variable regions are present on a single read.
// Input: dual_single.fastq
// Container: quay.io/biocontainers/bioconductor-screencounter:1.10.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCREENCOUNTER_DUAL_BARCODES_SINGLE_END {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-screencounter:1.10.0--r45ha27e39d_0"

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
    .bm_deps <- c("Biostrings", "S4Vectors", "screenCounter")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(screenCounter)
    library(Biostrings)
    library(S4Vectors)
    
    # Define input file
    input_fastq <- "dual_single.fastq"
    
    # Stage 1: Define valid barcode combinations in a DataFrame
    known.pool1 <- c("AGAGAGAGA", "CTCTCTCTC",
        "GTGTGTGTG", "CACACACAC")
    known.pool2 <- c("ATATATATA", "CGCGCGCGC",
        "GAGAGAGAG", "CTCTCTCTC")
    
    choices <- expand.grid(known.pool1, known.pool2)
    choices <- DataFrame(barcode1=choices[,1], barcode2=choices[,2])
    set.seed(42) # Ensure reproducible sampling of the choices DataFrame
    choices <- choices[sample(nrow(choices), nrow(choices)*0.9),]
    
    # Stage 2: Quantify single-end dual barcodes using matrixOfDualBarcodesSingleEnd
    out <- matrixOfDualBarcodesSingleEnd(input_fastq, choices=choices,
        template="CAGCTACGTACGNNNNNNNNNCCAGCTCGATCGNNNNNNNNNACACGAGGGTAT")
    
    # Stage 3: Extract the count matrix using assay
    counts_matrix <- assay(out)
    
    # Stage 4: Extract mapping diagnostics using colData
    mapping_diagnostics <- colData(out)
    
    # Stage 5: Extract barcode identities using rowData
    barcode_identities <- rowData(out)
    
    # Write outputs to files
    write.csv(as.matrix(counts_matrix), "barcode_counts.csv", row.names = TRUE)
    write.csv(as.data.frame(mapping_diagnostics), "mapping_diagnostics.csv", row.names = TRUE)
    write.csv(as.data.frame(barcode_identities), "barcode_identities.csv", row.names = TRUE)
    saveRDS(out, "dual_barcodes_single_end_results.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SCREENCOUNTER_DUAL_BARCODES_SINGLE_END":
        screencounter: \$(Rscript -e 'cat(as.character(packageVersion("screencounter")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dual_barcodes_single_end.csv versions.yml
    """
}

workflow BIOC_SCREENCOUNTER_DUAL_BARCODES_SINGLE_END_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dual_single.fastq ] ]

    main:
    BIOC_SCREENCOUNTER_DUAL_BARCODES_SINGLE_END(ch_input)

    emit:
    tables   = BIOC_SCREENCOUNTER_DUAL_BARCODES_SINGLE_END.out.tables
    plots    = BIOC_SCREENCOUNTER_DUAL_BARCODES_SINGLE_END.out.plots
    objects  = BIOC_SCREENCOUNTER_DUAL_BARCODES_SINGLE_END.out.objects
    versions = BIOC_SCREENCOUNTER_DUAL_BARCODES_SINGLE_END.out.versions
}
