#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dada2 — paired_end_denoising_pipeline
// Process raw paired-end FASTQ files to resolve exact amplicon sequence variants (ASVs) and construct a non-chimeric sequence table.
// Input: sample_F.fastq.gz, sample_R.fastq.gz
// Container: quay.io/biocontainers/bioconductor-dada2:1.38.0--r45ha27e39d_0
// R packages: dada2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DADA2_PAIRED_END_DENOISING_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-dada2:1.38.0--r45ha27e39d_0"

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
    .bm_deps <- c("dada2")
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
    
    # Load the required library
    library(dada2)
    cat("DADA2 version:", as.character(packageVersion("dada2")), "\n")
    
    # Define input files from the working directory as specified by the user
    fnF1 <- "sample_F.fastq.gz"
    fnR1 <- "sample_R.fastq.gz"
    
    # Define output paths for filtered reads
    filtF1 <- "sample_F_filtered.fastq.gz"
    filtR1 <- "sample_R_filtered.fastq.gz"
    
    # 1. Inspect quality profiles
    pdf("quality_profiles.pdf", width = 10, height = 7)
    plotQualityProfile(fnF1) # Forward
    plotQualityProfile(fnR1) # Reverse
    dev.off()
    
    # 2. Filter and trim reads
    filterAndTrim(fwd=fnF1, filt=filtF1, rev=fnR1, filt.rev=filtR1,
                  trimLeft=10, truncLen=c(240, 200), 
                  maxN=0, maxEE=2,
                  compress=TRUE, verbose=TRUE)
    
    # 3. Dereplicate filtered reads
    derepF1 <- derepFastq(filtF1, verbose=TRUE)
    derepR1 <- derepFastq(filtR1, verbose=TRUE)
    
    # 4. Learn error rates
    errF <- learnErrors(derepF1, multithread=FALSE)
    errR <- learnErrors(derepR1, multithread=FALSE)
    
    # Plot and save error rates for quality control
    pdf("error_rates.pdf", width = 10, height = 7)
    plotErrors(errF, nominalQ=TRUE)
    plotErrors(errR, nominalQ=TRUE)
    dev.off()
    
    # 5. Infer sample composition
    dadaF1 <- dada(derepF1, err=errF, multithread=FALSE)
    dadaR1 <- dada(derepR1, err=errR, multithread=FALSE)
    print(dadaF1)
    
    # 6. Merge forward and reverse reads
    merger1 <- mergePairs(dadaF1, derepF1, dadaR1, derepR1, verbose=TRUE)
    
    # Remove chimeras on the single merged sample (as shown in the first part of the vignette)
    merger1.nochim <- removeBimeraDenovo(merger1, multithread=FALSE, verbose=TRUE)
    
    # 7. Construct sequence table (adapted for the single user-provided sample)
    seqtab <- makeSequenceTable(list(merger1))
    
    # 8. Remove chimeras from the sequence table
    seqtab.nochim <- removeBimeraDenovo(seqtab, verbose=TRUE)
    print(dim(seqtab.nochim))
    
    # Save the final sequence table and results
    saveRDS(seqtab.nochim, "seqtab_nochim.rds")
    write.csv(as.data.frame(seqtab.nochim), "seqtab_nochim.csv", row.names = TRUE)
    
    cat("Pipeline completed successfully. Outputs saved to 'quality_profiles.pdf', 'error_rates.pdf', 'seqtab_nochim.rds', and 'seqtab_nochim.csv'.\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DADA2_PAIRED_END_DENOISING_PIPELINE":
        dada2: \$(Rscript -e 'cat(as.character(packageVersion("dada2")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_end_denoising_pipeline.csv versions.yml
    """
}

workflow BIOC_DADA2_PAIRED_END_DENOISING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_F.fastq.gz, sample_R.fastq.gz ] ]

    main:
    BIOC_DADA2_PAIRED_END_DENOISING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_DADA2_PAIRED_END_DENOISING_PIPELINE.out.tables
    plots    = BIOC_DADA2_PAIRED_END_DENOISING_PIPELINE.out.plots
    objects  = BIOC_DADA2_PAIRED_END_DENOISING_PIPELINE.out.objects
    versions = BIOC_DADA2_PAIRED_END_DENOISING_PIPELINE.out.versions
}
