#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomautomorphism — automorphism_analysis_3d_space
// Compute and analyze genomic automorphisms on the 3D space Z5^3 representing the genetic-code cube on the Galois field GF(5) to identify codon-preserving and mut
// Input: covid_aln
// Container: quay.io/biocontainers/bioconductor-genomautomorphism:1.12.0--r45hdfd78af_0
// R packages: Biostrings, GenomAutomorphism
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: bar plot

nextflow.enable.dsl = 2

process BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_3D_SPACE {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-genomautomorphism:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "GenomAutomorphism")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(Biostrings)
    library(GenomAutomorphism)
    
    # --- Load the pairwise sequence alignment from the working ---
    # We support reading 'covid_aln' either as a serialized RDS object or as a FASTA file.
    if (file.exists("covid_aln")) {
      covid_aln <- tryCatch({
        readRDS("covid_aln")
      }, error = function(e) {
        Biostrings::readDNAMultipleAlignment("covid_aln", format = "fasta")
      })
    } else if (file.exists("covid_aln.rds")) {
      covid_aln <- readRDS("covid_aln.rds")
    } else if (file.exists("covid_aln.fasta")) {
      covid_aln <- Biostrings::readDNAMultipleAlignment("covid_aln.fasta", format = "fasta")
    } else if (file.exists("covid_aln.fa")) {
      covid_aln <- Biostrings::readDNAMultipleAlignment("covid_aln.fa", format = "fasta")
    } else {
      stop("Error: Input file 'covid_aln' (RDS or FASTA format) not found in the working directory.")
    }
    
    # --- Compute automorphisms on the 3D space group Z5^3 using ---
    autm_3d <- automorphisms(
      seq = covid_aln,
      group = "Z5^3",
      cube = c("ACGT", "TGCA"),
      cube_alt = c("CATG", "GTAC"),
      verbose = FALSE
    )
    
    # --- Group automorphisms by coefficients to identify ---
    autby_coef_3d <- automorphism_bycoef(autm_3d)
    autby_coef_3d <- autby_coef_3d[ autby_coef_3d\$autm != "1,1,1" ]
    
    # --- Extract conserved genomic regions ---
    conserv <- conserved_regions(autm_3d)
    
    # Save results to output files
    # Save RDS objects
    saveRDS(autm_3d, "autm_3d.rds")
    saveRDS(autby_coef_3d, "autby_coef_3d.rds")
    saveRDS(conserv, "conserved_regions_3d.rds")
    
    # Save CSV tables for downstream analysis
    write.csv(as.data.frame(autby_coef_3d), "autby_coef_3d.csv", row.names = FALSE)
    write.csv(as.data.frame(conserv), "conserved_regions_3d.csv", row.names = FALSE)
    
    # Generate and save the automorphism distribution plot
    pdf("automorphism_distribution_3d.pdf", width = 6, height = 5)
    counts <- table(autby_coef_3d\$cube[ autby_coef_3d\$autm != "1,1,1" ])
    if (length(counts) > 0) {
      par(family = "serif", cex = 1, font = 2, cex.main = 1)
      barplot(counts, main = "Automorphism distribution",
              xlab = "Genetic-code cube representation",
              ylab = "Fixed mutational events",
              col = c("darkblue", "red"), 
              ylim = c(0, max(counts) * 1.2), 
              border = NA, axes = TRUE)
      mtext(side = 1, line = -2, at = seq(0.7, by = 1.2, length.out = length(counts)),
            text = paste0(counts), cex = 1.4, col = c("white"))
    }
    dev.off()

    writeLines(c(
        '"BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_3D_SPACE":',
        paste0('        genomautomorphism: ', as.character(packageVersion("genomautomorphism")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automorphism_analysis_3d_space.csv versions.yml
    """
}

workflow BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_3D_SPACE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ covid_aln ] ]

    main:
    BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_3D_SPACE(ch_input)

    emit:
    tables   = BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_3D_SPACE.out.tables
    plots    = BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_3D_SPACE.out.plots
    objects  = BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_3D_SPACE.out.objects
    versions = BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_3D_SPACE.out.versions
}
