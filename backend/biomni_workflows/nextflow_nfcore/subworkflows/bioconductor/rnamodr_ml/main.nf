#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rnamodr_ml — detect_2_o_methylations_ml
// Detect 2'-O-methylations from Ribo-meth-seq BAM files using machine learning classifiers.
// Input: sample1.bam, genome.fa, annotation.gff
// Container: quay.io/biocontainers/r-base:4.3.1
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/r-base:4.3.1"

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
    .bm_deps <- c("genomicranges", "rnamodr.ml", "rnamodr_ml", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # 1. Load the package and define input file paths
    library(rnamodr.ml)
    
    # User-specified input files
    bamfiles <- "sample1.bam"
    fasta <- "genome.fa"
    gff <- "annotation.gff"
    
    # Robustness: Attempt to index the BAM file if the index does not exist
    if (file.exists("sample1.bam") && !file.exists("sample1.bam.bai")) {
      tryCatch({
        if (requireNamespace("Rsamtools", quietly = TRUE)) {
          Rsamtools::indexBam("sample1.bam")
        }
      }, error = function(e) {
        warning("Optional BAM indexing failed: ", e\$message)
      })
    }
    
    # 2. Initialize the ModMLRiboMethSeq modifier object
    mod <- ModMLRiboMethSeq(bamfiles, fasta = fasta, gff = gff)
    
    # 3. Extract predicted 2'-O-methylations using the modifications function
    mods <- modifications(mod)
    
    # 4. Write named output files for the results
    saveRDS(mod, "rnamodr_modifier_object.rds")
    saveRDS(mods, "predicted_modifications.rds")
    
    # Attempt to save modifications as a CSV table for easy viewing
    tryCatch({
      mods_df <- as.data.frame(mods)
      write.csv(mods_df, "predicted_modifications.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not write modifications to CSV: ", e\$message)
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML":
        rnamodr_ml: \$(Rscript -e 'cat(as.character(packageVersion("rnamodr_ml")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_detect_2_o_methylations_ml.csv versions.yml
    """
}

workflow BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample1.bam, genome.fa, annotation.gff ] ]

    main:
    BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML(ch_input)

    emit:
    tables   = BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML.out.tables
    plots    = BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML.out.plots
    objects  = BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML.out.objects
    versions = BIOC_RNAMODR_ML_DETECT_2_O_METHYLATIONS_ML.out.versions
}
