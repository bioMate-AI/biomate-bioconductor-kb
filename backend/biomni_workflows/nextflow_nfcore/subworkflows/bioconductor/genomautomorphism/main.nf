#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: genomautomorphism — automorphism_analysis_1d_group
// Compute and analyze genomic automorphisms on 1D cyclic groups (Z64 or Z125) from pairwise aligned DNA sequences to identify mutational events, indels, and estim
// Input: covid_aln
// Container: quay.io/biocontainers/bioconductor-genomautomorphism:1.12.0--r45hdfd78af_0
// R packages: Biostrings, GenomAutomorphism
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_1D_GROUP {
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
    # The pipeline expects 'covid_aln' as a DNAMultipleAlignment object.
    # We support reading it from an RDS file or a FASTA file.
    if (file.exists("covid_aln.rds")) {
      covid_aln <- readRDS("covid_aln.rds")
    } else if (file.exists("covid_aln")) {
      covid_aln <- tryCatch({
        readRDS("covid_aln")
      }, error = function(e) {
        Biostrings::readDNAMultipleAlignment("covid_aln")
      })
    } else if (file.exists("covid_aln.fasta")) {
      covid_aln <- Biostrings::readDNAMultipleAlignment("covid_aln.fasta")
    } else if (file.exists("covid_aln.fa")) {
      covid_aln <- Biostrings::readDNAMultipleAlignment("covid_aln.fa")
    } else {
      stop("Required input file 'covid_aln' (RDS or FASTA format) not found in the working directory.")
    }
    
    # --- Compute codon coordinates on the specified group ---
    codons <- codon_coord(
                        codon = covid_aln, 
                        cube = "ACGT", 
                        group = "Z64", 
                        chr = 1L,
                        strand = "+",
                        start = 1,
                        end = 750)
    
    # Save codon coordinates
    saveRDS(codons, "codons_coord.rds")
    
    # --- Compute automorphisms on the 1D cyclic group (Z64) using ---
    autm <- automorphisms(
                        seqs = covid_aln,
                        group = "Z64",
                        cube = c("ACGT", "TGCA"),
                        cube_alt = c("CATG", "GTAC"),
                        start = 1,
                        end = 750, 
                        verbose = FALSE)
    
    saveRDS(autm, "autm_z64_750.rds")
    
    # --- Summarize the automorphism results by genomic ranges to ---
    aut_range <- automorphismByRanges(autm)
    
    # Compute full-length automorphisms on Z64 (replacing package data loading)
    covid_autm <- automorphisms(
                        seqs = covid_aln,
                        group = "Z64",
                        cube = c("ACGT", "TGCA"),
                        cube_alt = c("CATG", "GTAC"),
                        verbose = FALSE)
    
    saveRDS(covid_autm, "covid_autm_z64.rds")
    
    aut_range <- automorphismByRanges(covid_autm)
    saveRDS(aut_range, "aut_range_z64.rds")
    write.csv(as.data.frame(aut_range), "aut_range_z64.csv", row.names = FALSE)
    
    # Identify indels (translations)
    idx = which(covid_autm\$cube == "Trnl")
    covid_autm_trnl <- covid_autm[ idx ]
    saveRDS(covid_autm_trnl, "covid_autm_trnl.rds")
    
    idx = which(aut_range\$cube == "Trnl")
    aut_range_trnl <- aut_range[ idx ]
    saveRDS(aut_range_trnl, "aut_range_trnl.rds")
    
    df_trnl <- data.frame(aut_range[idx])
    write.csv(df_trnl, "aut_range_trnl.csv", row.names = FALSE)
    
    trnl_widths <- width(aut_range[ idx ])
    saveRDS(trnl_widths, "trnl_widths.rds")
    
    # Generate and save Automorphism distribution by cubes plot
    pdf("automorphism_distribution_z64.pdf", width = 7, height = 6)
    counts_cubes <- table(covid_autm\$cube[ covid_autm\$autm != 1 | is.na(covid_autm\$autm) ])
    par(family = "serif", cex = 0.9, font = 2, mar = c(4, 6, 4, 4))
    barplot(counts_cubes, main = "Automorphism distribution",
            xlab = "Genetic-code cube representation",
            ylab = "Fixed mutational events",
            col = c("darkblue", "red", "darkgreen"), 
            border = NA, axes = FALSE, 
            cex.lab = 2, cex.main = 1.5, cex.names = 2)
    axis(2, at = c(0, 200, 400, 600, 800), cex.axis = 1.5)
    mtext(side = 1, line = -1.5, at = c(0.7, 1.9, 3.1, 4.3, 5.5),
          text = paste0(counts_cubes), cex = 1.4,
          col = c("white", "yellow", "black"))
    dev.off()
    
    # --- Group automorphisms by coefficients to classify mutation ---
    autby_coef <- automorphism_bycoef(covid_autm)
    autby_coef <- autby_coef[ autby_coef\$autm != 1 & autby_coef\$autm != -1  ]
    
    saveRDS(autby_coef, "autby_coef.rds")
    write.csv(as.data.frame(autby_coef), "autby_coef.csv", row.names = FALSE)
    
    # --- Estimate the posterior probabilities of mutation types ---
    post_prob <- automorphism_prob(autby_coef)
    
    # Generate and save Automorphism distribution per Mutation type plot
    pdf("automorphism_distribution_by_mutation_type.pdf", width = 14, height = 12)
    counts_mut <- post_prob\$frequency
    names(counts_mut) <- post_prob\$Codon
    counts_mut <- counts_mut[counts_mut > 2]
    par(family = "serif", cex.axis = 2, font = 2, las = 1, 
        cex.main = 2.2, mar = c(6, 2, 4, 4))
    barplot(counts_mut, main = "Automorphism distribution per Mutation type",
            col = colorRampPalette(c("red", "yellow", "blue"))(36), 
            border = NA, axes = FALSE, las = 2)
    axis(side = 2, cex.axis = 2, line = -1.8)
    dev.off()
    
    # Filter by posterior probability threshold
    post_prob <- post_prob[post_prob\$Posterior_Probability > 0.003,]
    saveRDS(post_prob, "post_prob.rds")
    write.csv(post_prob, "post_prob.csv", row.names = FALSE)
    
    # Generate and save Automorphism Probability per Mutation type plot
    pdf("automorphism_probability_by_mutation_type.pdf", width = 14, height = 12)
    probs <- post_prob\$Posterior_Probability
    names(probs) <- post_prob\$Codon
    par(family = "serif", cex.axis = 2, font = 2, las = 1, 
        cex.main = 2.1, mar = c(7, 2, 4, 2))
    barplot(probs, main = "Automorphism Probaility per Mutation type",
            col = colorRampPalette(c("red", "yellow", "blue"))(36), 
            border = NA, axes = FALSE, las = 2, hadj = 0.8)
    axis(side = 2, cex.axis = 2.1, line = -1.8, hadj = 0.9)
    dev.off()
    
    # --- Extract conserved and unique conserved genomic regions ---
    conserv <- conserved_regions(covid_autm)
    saveRDS(conserv, "conserved_regions.rds")
    write.csv(as.data.frame(conserv), "conserved_regions.csv", row.names = FALSE)
    
    conserv_unique <- conserved_regions(covid_autm, output = "unique")
    saveRDS(conserv_unique, "conserved_regions_unique.rds")
    write.csv(as.data.frame(conserv_unique), "conserved_regions_unique.csv", row.names = FALSE)
    
    # --- Compute automorphisms on the 1D cyclic group (Z125) ---
    autm_z125 <- automorphisms(
                        seqs = covid_aln,
                        group = "Z125",
                        cube = c("ACGT", "TGCA"),
                        cube_alt = c("CATG", "GTAC"),
                        verbose = FALSE)
    
    saveRDS(autm_z125, "autm_z125.rds")
    
    aut_range_2 <- automorphismByRanges(autm_z125)
    saveRDS(aut_range_2, "aut_range_z125.rds")
    write.csv(as.data.frame(aut_range_2), "aut_range_z125.csv", row.names = FALSE)
    
    # Generate and save Automorphism distribution Z125 plot
    pdf("automorphism_distribution_z125.pdf", width = 5, height = 5)
    counts_z125 <- table(autm_z125\$cube[ autm_z125\$autm != 1 ])
    par(family = "serif", cex = 1, font = 2)
    barplot(counts_z125, main = "Automorphism distribution",
            xlab = "Genetic-code cube representation",
            ylab = "Fixed mutational events",
            col = c("darkblue", "red"), 
            ylim = c(0, 1300),
            border = NA, axes = TRUE)
    mtext(side = 1, line = -2, at = c(0.7, 1.9, 3.1),
          text = paste0(counts_z125), cex = 1.4,
          col = c("white", "red"))
    dev.off()

    writeLines(c(
        '"BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_1D_GROUP":',
        paste0('        genomautomorphism: ', as.character(packageVersion("genomautomorphism")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automorphism_analysis_1d_group.csv versions.yml
    """
}

workflow BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_1D_GROUP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ covid_aln ] ]

    main:
    BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_1D_GROUP(ch_input)

    emit:
    tables   = BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_1D_GROUP.out.tables
    plots    = BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_1D_GROUP.out.plots
    objects  = BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_1D_GROUP.out.objects
    versions = BIOC_GENOMAUTOMORPHISM_AUTOMORPHISM_ANALYSIS_1D_GROUP.out.versions
}
