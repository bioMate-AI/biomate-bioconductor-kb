#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mungesumstats — liftover_genome_build
// Perform genome build liftover (e.g., hg19 to hg38) on a summary statistics data.table.
// Input: sumstats_dt
// Container: quay.io/biocontainers/bioconductor-mungesumstats:1.18.1--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUNGESUMSTATS_LIFTOVER_GENOME_BUILD {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-mungesumstats:1.18.1--r45hdfd78af_0"

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
    .bm_deps <- c("MungeSumstats", "data.table")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(data.table)
    library(MungeSumstats)
    
    # 1. Load the summary statistics from the user input file 'sumstats_dt'
    # We attempt to read it as an RDS object first, and fallback to data.table::fread
    if (file.exists("sumstats_dt")) {
      sumstats_dt <- tryCatch({
        readRDS("sumstats_dt")
      }, error = function(e) {
        data.table::fread("sumstats_dt")
      })
    } else if (file.exists("sumstats_dt.rds")) {
      sumstats_dt <- readRDS("sumstats_dt.rds")
    } else if (file.exists("sumstats_dt.tsv")) {
      sumstats_dt <- data.table::fread("sumstats_dt.tsv")
    } else if (file.exists("sumstats_dt.csv")) {
      sumstats_dt <- data.table::fread("sumstats_dt.csv")
    } else if (file.exists("sumstats_dt.txt")) {
      sumstats_dt <- data.table::fread("sumstats_dt.txt")
    } else {
      stop("Required input file 'sumstats_dt' (or with .rds/.tsv/.csv/.txt extension) not found in the working directory.")
    }
    
    # Ensure the input is a data.table
    if (!data.table::is.data.table(sumstats_dt)) {
      sumstats_dt <- data.table::as.data.table(sumstats_dt)
    }
    
    # 2. Run liftover specifying the source and target genome builds
    sumstats_dt_hg38 <- MungeSumstats::liftover(sumstats_dt = sumstats_dt, ref_genome = "hg19", convert_ref_genome = "hg38")
    
    # 3. Write named output files for the meaningful results
    data.table::fwrite(sumstats_dt_hg38, "sumstats_dt_hg38.tsv", sep = "\t", quote = FALSE, row.names = FALSE)
    saveRDS(sumstats_dt_hg38, "sumstats_dt_hg38.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MUNGESUMSTATS_LIFTOVER_GENOME_BUILD":
        mungesumstats: \$(Rscript -e 'cat(as.character(packageVersion("mungesumstats")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_liftover_genome_build.csv versions.yml
    """
}

workflow BIOC_MUNGESUMSTATS_LIFTOVER_GENOME_BUILD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sumstats_dt ] ]

    main:
    BIOC_MUNGESUMSTATS_LIFTOVER_GENOME_BUILD(ch_input)

    emit:
    tables   = BIOC_MUNGESUMSTATS_LIFTOVER_GENOME_BUILD.out.tables
    plots    = BIOC_MUNGESUMSTATS_LIFTOVER_GENOME_BUILD.out.plots
    objects  = BIOC_MUNGESUMSTATS_LIFTOVER_GENOME_BUILD.out.objects
    versions = BIOC_MUNGESUMSTATS_LIFTOVER_GENOME_BUILD.out.versions
}
