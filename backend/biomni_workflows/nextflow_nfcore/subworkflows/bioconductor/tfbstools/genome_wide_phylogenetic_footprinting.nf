#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: tfbstools — genome_wide_phylogenetic_footprinting
// Identify conserved TFBSs across two genomes using liftover chain files.
// Input: hg19_genome, mm10_genome, hg19ToMm10.over.chain
// Container: quay.io/biocontainers/bioconductor-tfbstools:1.48.0--r45h01b2380_0
// R packages: BSgenome, JASPAR2014, TFBSTools, rtracklayer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TFBSTOOLS_GENOME_WIDE_PHYLOGENETIC_FOOTPRINTING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-tfbstools:1.48.0--r45h01b2380_0"

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
    .bm_deps <- c("BSgenome", "JASPAR2014", "TFBSTools", "rtracklayer")
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
    library(TFBSTools)
    library(rtracklayer)
    library(JASPAR2014)
    library(BSgenome)
    
    # Read the declared USER INPUT files from the working directory
    # The BSgenome objects are stored as RDS files in the working directory
    BSgenome.Hsapiens.UCSC.hg19 <- readRDS("hg19_genome")
    BSgenome.Mmusculus.UCSC.mm10 <- readRDS("mm10_genome")
    chain <- import.chain("hg19ToMm10.over.chain")
    
    # 1. Retrieve PFM and convert to PWM
    pfm <- getMatrixByID(JASPAR2014, ID="MA0004.1")
    pwm <- toPWM(pfm)
    
    # 2. Scan both genomes using liftover chain to find conserved sites
    sitePairSet <- searchPairBSgenome(pwm, BSgenome.Hsapiens.UCSC.hg19,
                                     BSgenome.Mmusculus.UCSC.mm10,
                                     chr1="chr1", chr2="chr1",
                                     min.score="90%", strand="+", chain=chain)
    
    # Save meaningful results to output files
    saveRDS(sitePairSet, "sitePairSet.rds")
    
    # Export the identified conserved sites to a GFF3-formatted CSV table
    gff3_df <- writeGFF3(sitePairSet)
    write.csv(gff3_df, "sitePairSet_gff3.csv", row.names=FALSE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_TFBSTOOLS_GENOME_WIDE_PHYLOGENETIC_FOOTPRINTING":
        tfbstools: \$(Rscript -e 'cat(as.character(packageVersion("tfbstools")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genome_wide_phylogenetic_footprinting.csv versions.yml
    """
}

workflow BIOC_TFBSTOOLS_GENOME_WIDE_PHYLOGENETIC_FOOTPRINTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hg19_genome, mm10_genome, hg19ToMm10.over.chain ] ]

    main:
    BIOC_TFBSTOOLS_GENOME_WIDE_PHYLOGENETIC_FOOTPRINTING(ch_input)

    emit:
    tables   = BIOC_TFBSTOOLS_GENOME_WIDE_PHYLOGENETIC_FOOTPRINTING.out.tables
    plots    = BIOC_TFBSTOOLS_GENOME_WIDE_PHYLOGENETIC_FOOTPRINTING.out.plots
    objects  = BIOC_TFBSTOOLS_GENOME_WIDE_PHYLOGENETIC_FOOTPRINTING.out.objects
    versions = BIOC_TFBSTOOLS_GENOME_WIDE_PHYLOGENETIC_FOOTPRINTING.out.versions
}
