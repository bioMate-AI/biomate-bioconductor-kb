#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rsubread — bulk_rna_seq_alignment_and_quantification
// Align bulk RNA-seq reads to a reference genome and quantify gene-level expression.
// Input: reference.fa, reads.txt.gz, reads1.txt.gz, reads2.txt.gz
// Container: quay.io/biocontainers/bioconductor-rsubread:2.24.0--r45h01b2380_0
// R packages: Rsubread
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RSUBREAD_BULK_RNA_SEQ_ALIGNMENT_AND_QUANTIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-rsubread:2.24.0--r45h01b2380_0"

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
    .bm_deps <- c("Rsubread")
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
    
    # Load required library
    library(Rsubread)
    
    # Define input file paths as specified by the user
    ref <- "reference.fa"
    reads <- "reads.txt.gz"
    reads1 <- "reads1.txt.gz"
    reads2 <- "reads2.txt.gz"
    
    # Verify input files exist before proceeding
    input_files <- c(ref, reads, reads1, reads2)
    missing_files <- input_files[!file.exists(input_files)]
    if (length(missing_files) > 0) {
      stop(paste("Missing required input file(s):", paste(missing_files, collapse=", ")))
    }
    
    # 1. Build reference genome index
    buildindex(basename="reference_index",reference=ref)
    
    # 2. Align single-end reads
    align.stat <- align(index="reference_index",readfile1=reads,output_file="alignResults.BAM",phredOffset=64)
    
    # 3. Align paired-end reads
    align.stat2 <- align(index="reference_index",readfile1=reads1,readfile2=reads2,output_file="alignResultsPE.BAM",phredOffset=64)
    
    # 4. Define annotation (exactly as documented)
    ann <- data.frame(
      GeneID=c("gene1","gene1","gene2","gene2"),
      Chr="chr_dummy",
      Start=c(100,1000,3000,5000),
      End=c(500,1800,4000,5500),
      Strand=c("+","+","-","-"),
      stringsAsFactors=FALSE
    )
    
    # 5. Quantify gene-level expression for single-end alignment
    fc_SE <- featureCounts("alignResults.BAM",annot.ext=ann)
    
    # 6. Quantify gene-level expression for paired-end alignment
    fc_PE <- featureCounts("alignResultsPE.BAM",annot.ext=ann,isPairedEnd=TRUE)
    
    # Save outputs to disk
    write.csv(align.stat, file="align_stat_SE.csv", row.names=TRUE)
    write.csv(align.stat2, file="align_stat_PE.csv", row.names=TRUE)
    write.csv(fc_SE\$counts, file="featureCounts_SE_counts.csv", row.names=TRUE)
    write.csv(fc_PE\$counts, file="featureCounts_PE_counts.csv", row.names=TRUE)
    write.csv(fc_SE\$stat, file="featureCounts_SE_stats.csv", row.names=TRUE)
    write.csv(fc_PE\$stat, file="featureCounts_PE_stats.csv", row.names=TRUE)
    
    saveRDS(fc_SE, file="fc_SE.rds")
    saveRDS(fc_PE, file="fc_PE.rds")
    
    cat("Pipeline completed successfully. Outputs saved.\n")

    writeLines(c(
        '"BIOC_RSUBREAD_BULK_RNA_SEQ_ALIGNMENT_AND_QUANTIFICATION":',
        paste0('        rsubread: ', as.character(packageVersion("rsubread")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bulk_rna_seq_alignment_and_quantification.csv versions.yml
    """
}

workflow BIOC_RSUBREAD_BULK_RNA_SEQ_ALIGNMENT_AND_QUANTIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reference.fa, reads.txt.gz, reads1.txt.gz, reads2.txt.gz ] ]

    main:
    BIOC_RSUBREAD_BULK_RNA_SEQ_ALIGNMENT_AND_QUANTIFICATION(ch_input)

    emit:
    tables   = BIOC_RSUBREAD_BULK_RNA_SEQ_ALIGNMENT_AND_QUANTIFICATION.out.tables
    plots    = BIOC_RSUBREAD_BULK_RNA_SEQ_ALIGNMENT_AND_QUANTIFICATION.out.plots
    objects  = BIOC_RSUBREAD_BULK_RNA_SEQ_ALIGNMENT_AND_QUANTIFICATION.out.objects
    versions = BIOC_RSUBREAD_BULK_RNA_SEQ_ALIGNMENT_AND_QUANTIFICATION.out.versions
}
