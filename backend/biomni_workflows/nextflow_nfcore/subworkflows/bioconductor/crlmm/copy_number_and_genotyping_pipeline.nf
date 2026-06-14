#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crlmm — copy_number_and_genotyping_pipeline
// Preprocess, genotype, and estimate copy number (including allele-specific copy number, log R ratios, and B allele frequencies) using a disk-backed CNSet contain
// Input: celFiles
// Container: quay.io/biocontainers/bioconductor-crlmm:1.68.0--r45h01b2380_0
// R packages: VanillaICE, crlmm, ff, lattice, oligoClasses
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)
// QC: missing-value handling

nextflow.enable.dsl = 2

process BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-crlmm:1.68.0--r45h01b2380_0"

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
    .bm_deps <- c("VanillaICE", "crlmm", "ff", "lattice", "oligoClasses")
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
    
    # Load required libraries
    library(oligoClasses)
    library(crlmm)
    library(ff)
    library(VanillaICE)
    library(lattice)
    
    # --- Set up disk-backed storage and RAM limits ---
    outdir <- "./crlmm_output"
    if (!dir.exists(outdir)) {
      dir.create(outdir, recursive = TRUE)
    }
    ldPath(outdir)
    ocProbesets(100000)
    ocSamples(200)
    
    # Read user input CEL files from the working directory
    if (!exists("celFiles")) {
      celFiles <- list.celfiles(".", full.names = TRUE, pattern = "\\\\.CEL\$", ignore.case = TRUE)
    }
    
    if (length(celFiles) == 0) {
      stop("Error: No CEL files found in the working directory. Please provide raw Affymetrix CEL files.")
    }
    
    # Extract batch/plate information from CEL filenames
    plates <- substr(basename(celFiles), 13, 13)
    
    # --- Construct the CNSet container ---
    cnSet <- constructAffyCNSet(celFiles, batch=plates, cdfName="genomewidesnp6", genome="hg19")
    
    # --- Perform quantile normalization ---
    cnrmaAffy(cnSet)
    validCEL(celFiles)
    snprmaAffy(cnSet)
    
    # --- Genotype and impute gender ---
    genotypeAffy(cnSet, gender=NULL)
    gender_table <- table(c("male", "female")[cnSet\$gender[]])
    print(gender_table)
    
    # --- Fit linear model for copy number ---
    crlmmCopynumber(cnSet)
    
    # --- Extract raw copy number or coerce to BafLrrSetList for ---
    tmp <- totalCopynumber(cnSet, i=seq_len(nrow(cnSet)), j=1:2)
    snp.index <- which(isSnp(cnSet) & !is.na(chromosome(cnSet)))
    ca <- CA(cnSet, i=snp.index, j=1:2)
    cb <- CB(cnSet, i=snp.index, j=1:2)
    
    open(cnSet)
    oligoSetList <- BafLrrSetList(cnSet)
    close(cnSet)
    
    lrrList <- lrr(oligoSetList)
    bafList <- baf(oligoSetList)
    
    # Save meaningful results to output files
    saveRDS(cnSet, file = file.path(outdir, "cnSet.rds"))
    write.csv(as.data.frame(gender_table), file = file.path(outdir, "gender_table.csv"), row.names = FALSE)
    saveRDS(tmp, file = file.path(outdir, "total_copynumber_sample1_2.rds"))
    saveRDS(ca, file = file.path(outdir, "CA_sample1_2.rds"))
    saveRDS(cb, file = file.path(outdir, "CB_sample1_2.rds"))
    saveRDS(oligoSetList, file = file.path(outdir, "oligoSetList.rds"))
    saveRDS(lrrList, file = file.path(outdir, "lrrList.rds"))
    saveRDS(bafList, file = file.path(outdir, "bafList.rds"))
    
    # Generate and save SNR Quality Control Plot
    invisible(open(cnSet\$SNR))
    snr <- cnSet\$SNR[]
    close(cnSet\$SNR)
    
    pdf(file.path(outdir, "snr_histogram.pdf"))
    print(histogram(~snr,
                    panel=function(...){
                            panel.histogram(...)},
                    breaks=25, xlim=range(snr), xlab="SNR"))
    dev.off()
    
    cat("Pipeline completed successfully. Outputs saved to:", outdir, "\n")

    writeLines(c(
        '"BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE":',
        paste0('        crlmm: ', as.character(packageVersion("crlmm")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_copy_number_and_genotyping_pipeline.csv versions.yml
    """
}

workflow BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ celFiles ] ]

    main:
    BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE(ch_input)

    emit:
    tables   = BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE.out.tables
    plots    = BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE.out.plots
    objects  = BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE.out.objects
    versions = BIOC_CRLMM_COPY_NUMBER_AND_GENOTYPING_PIPELINE.out.versions
}
