#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: deepsnv — shearwater_bayes_factor
// Call subclonal mutations across multiple BAM files using the original Shearwater Bayes factor algorithm and output a VCF file.
// Input: files
// Container: quay.io/biocontainers/bioconductor-deepsnv:1.56.0--r45ha27e39d_0
// R packages: GenomicRanges, Rsamtools, VariantAnnotation, deepSNV
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DEEPSNV_SHEARWATER_BAYES_FACTOR {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-deepsnv:1.56.0--r45ha27e39d_0"

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
    .bm_deps <- c("GenomicRanges", "Rsamtools", "VariantAnnotation", "deepSNV")
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
    library(deepSNV)
    library(GenomicRanges)
    library(VariantAnnotation)
    library(Rsamtools)
    
    # Locate BAM files in the working directory
    files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
    if (length(files) == 0) {
      stop("Error: No BAM files found in the working directory. Please provide BAM files to run the pipeline.")
    }
    
    # 1. Define genomic regions of interest
    # Dynamically extract the first chromosome and a 21 bp region from the BAM header
    # to ensure compatibility with any user-provided BAM files.
    bam_header <- scanBamHeader(files[1])
    targets <- bam_header[[1]]\$targets
    if (length(targets) > 0) {
      chr <- names(targets)[1]
      target_len <- targets[1]
      start_pos <- max(1, floor(target_len / 2) - 10)
      end_pos <- min(target_len, start_pos + 20)
      regions <- GRanges(chr, IRanges(start = start_pos, end = end_pos))
    } else {
      regions <- GRanges("B.FR.83.HXB2_LAI_IIIB_BRU_K034", IRanges(start = 3120, end = 3140))
    }
    
    # 2. Load count data from BAM files
    counts <- loadAllData(files, regions, q=10)
    
    # 3. Compute Bayes factors
    bf <- bbb(counts, model = "OR", rho=1e-4)
    
    # 4. Convert Bayes factors to VCF format
    vcf <- bf2Vcf(bf, counts, regions, cutoff = 0.5, samples = files, prior = 0.5, mvcf = TRUE)
    
    # Write outputs
    writeVcf(vcf, "shearwater_calls.vcf")
    saveRDS(bf, "shearwater_bayes_factors.rds")
    saveRDS(counts, "shearwater_counts.rds")
    
    # Export a summary table of the VCF
    if (length(vcf) > 0) {
      vcf_df <- as.data.frame(info(vcf))
      write.csv(vcf_df, "shearwater_calls_summary.csv", row.names = TRUE)
    } else {
      write.csv(data.frame(Message = "No variants passed the cutoff threshold."), 
                "shearwater_calls_summary.csv", row.names = FALSE)
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DEEPSNV_SHEARWATER_BAYES_FACTOR":
        deepsnv: \$(Rscript -e 'cat(as.character(packageVersion("deepsnv")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_shearwater_bayes_factor.csv versions.yml
    """
}

workflow BIOC_DEEPSNV_SHEARWATER_BAYES_FACTOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files ] ]

    main:
    BIOC_DEEPSNV_SHEARWATER_BAYES_FACTOR(ch_input)

    emit:
    tables   = BIOC_DEEPSNV_SHEARWATER_BAYES_FACTOR.out.tables
    plots    = BIOC_DEEPSNV_SHEARWATER_BAYES_FACTOR.out.plots
    objects  = BIOC_DEEPSNV_SHEARWATER_BAYES_FACTOR.out.objects
    versions = BIOC_DEEPSNV_SHEARWATER_BAYES_FACTOR.out.versions
}
