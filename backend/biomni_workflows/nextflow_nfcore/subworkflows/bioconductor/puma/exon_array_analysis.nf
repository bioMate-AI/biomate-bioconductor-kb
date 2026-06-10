#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: puma — exon_array_analysis
// Calculate gene and transcript expression levels from Affymetrix exon arrays.
// Input: exonFilenames, SampleNameTable
// Container: quay.io/biocontainers/bioconductor-puma:3.52.0--r45h01b2380_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PUMA_EXON_ARRAY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-puma:3.52.0--r45h01b2380_0"

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
    .bm_deps <- c("oligo", "puma", "pumadata")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    library(puma)
    library(oligo)
    if (requireNamespace("pumadata", quietly = TRUE)) {
      library(pumadata)
    }
    
    # 1. Read CEL files and SampleNameTable from the working directory
    SampleNameTable_file <- "SampleNameTable"
    sample_info <- read.table(SampleNameTable_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    exonFilenames <- sample_info\$Celnames
    
    oligo.exon <- read.celfiles(exonFilenames)
    
    # 2. Calculate gene and transcript expression levels using gmoExon
    eset_gmoExon <- gmoExon(oligo.exon, exontype = "Human", gsnorm = "none")
    
    # 3. Write expression and standard error results to CSV files for gmoExon
    write.reslts(eset_gmoExon\$gene, file = "eset_gmoExon_gene")
    write.reslts(eset_gmoExon\$transcript, file = "eset_gmoExon_transcript")
    
    # 4. Calculate gene and transcript expression levels using igmoExon
    cel.path <- "."
    SampleNameTable <- "SampleNameTable"
    eset_igmoExon <- igmoExon(cel.path = cel.path, SampleNameTable = SampleNameTable,
                              exontype = "Human", gsnorm = "none", condition = "Yes")
    
    # 5. Write expression and standard error results to CSV files for igmoExon
    write.reslts(eset_igmoExon\$gene, file = "eset_igmoExon_gene")
    write.reslts(eset_igmoExon\$transcript, file = "eset_igmoExon_transcript")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PUMA_EXON_ARRAY_ANALYSIS":
        puma: \$(Rscript -e 'cat(as.character(packageVersion("puma")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_exon_array_analysis.csv versions.yml
    """
}

workflow BIOC_PUMA_EXON_ARRAY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exonFilenames, SampleNameTable ] ]

    main:
    BIOC_PUMA_EXON_ARRAY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PUMA_EXON_ARRAY_ANALYSIS.out.tables
    plots    = BIOC_PUMA_EXON_ARRAY_ANALYSIS.out.plots
    objects  = BIOC_PUMA_EXON_ARRAY_ANALYSIS.out.objects
    versions = BIOC_PUMA_EXON_ARRAY_ANALYSIS.out.versions
}
