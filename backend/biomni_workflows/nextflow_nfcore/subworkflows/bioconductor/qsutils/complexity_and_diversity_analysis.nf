#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: QSutils — complexity_and_diversity_analysis
// Compute incidence-based, abundance-based, and functional diversity indices to characterize quasispecies complexity, and apply sample size corrections.
// Input: ToyData_10_50_1000.fna
// Container: quay.io/biocontainers/bioconductor-qsutils:1.28.0--r45hdfd78af_0
// R packages: Biostrings, QSutils, ape, pwalign
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, QSutils, ape, pwalign
// Visualizations: diversity plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load quasispecies data using ReadAmplSeqs
//  * 2. [Core Analysis] Compute incidence-based indices (haplotype count, SegSites, TotalMutations)
//  * 3. [Core Analysis] Compute abundance-based indices (Shannon, GiniSimpson, Hill, Renyi, HCq)
//  * 4. [Core Analysis] Compute functional diversity indices using genetic distances (MutationFreq, FAD, NucleotideDiversity, RaoPow)

nextflow.enable.dsl = 2

process BIOC_QSUTILS_COMPLEXITY_AND_DIVERSITY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("Biostrings", "QSutils", "ape", "pwalign")
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
    library(QSutils)
    library(Biostrings)
    library(ape)
    library(pwalign)
    
    # Define input file path
    filepath <- "ToyData_10_50_1000.fna"
    
    # Verify input file existence
    if (!file.exists(filepath)) {
      stop(paste("Required input file missing:", filepath))
    }
    
    # 1. Load quasispecies data using ReadAmplSeqs
    lst <- ReadAmplSeqs(filepath, type="DNA")
    
    # Apply sample size corrections
    keep_idx <- DSFT(lst\$nr, sum(lst\$nr))
    lst\$nr <- lst\$nr[keep_idx]
    lst\$hseqs <- lst\$hseqs[keep_idx]
    
    # 2. Compute incidence-based indices
    h_count <- length(lst\$hseqs)
    seg_sites <- SegSites(lst\$hseqs)
    tot_muts <- TotalMutations(lst\$hseqs)
    
    # 3. Compute abundance-based indices
    shannon_val <- Shannon(lst\$nr)
    norm_shannon_val <- NormShannon(lst\$nr)
    shannon_var <- ShannonVar(lst\$nr)
    norm_shannon_var <- NormShannonVar(lst\$nr)
    gini_simpson <- GiniSimpson(lst\$nr)
    gini_simpson_mvue <- GiniSimpsonMVUE(lst\$nr)
    gini_simpson_var <- GiniSimpsonVar(lst\$nr)
    hill_q1 <- Hill(lst\$nr, q=1)
    hill_prof <- HillProfile(lst\$nr)
    renyi_q3 <- Renyi(lst\$nr, q=3)
    renyi_prof <- RenyiProfile(lst\$nr)
    hcq_q4 <- HCq(lst\$nr, q=4)
    hcq_var_q4 <- HCqVar(lst\$nr, q=4)
    hcq_prof <- HCqProfile(lst\$nr)
    
    # 4. Compute functional diversity indices using genetic distances
    dst <- DNA.dist(lst\$hseqs, model="raw")
    mut_freq_dst <- MutationFreq(dst)
    fad_dst <- FAD(dst)
    nuc_div_dst <- NucleotideDiversity(dst)
    
    nm <- nmismatch(pairwiseAlignment(lst\$hseqs, lst\$hseqs[1]))
    mut_freq_nm <- MutationFreq(nm=nm, nr=lst\$nr, len=width(lst\$hseqs)[1])
    mut_freq_var_nm <- MutationFreqVar(nm, lst\$nr, len=width(lst\$hseqs)[1])
    nuc_div_dst_nr <- NucleotideDiversity(dst, lst\$nr)
    rao_pow_q4 <- RaoPow(dst, 4, lst\$nr)
    rao_var <- RaoVar(dst, lst\$nr)
    rao_prof <- RaoPowProfile(dst, lst\$nr)
    
    # Write meaningful results to output files
    
    # Save summary of single-value indices
    summary_df <- data.frame(
      Metric = c(
        "Haplotype Count", "Segregating Sites", "Total Mutations",
        "Shannon Entropy", "Normalized Shannon Entropy", "Shannon Variance", "Normalized Shannon Variance",
        "Gini-Simpson", "Gini-Simpson MVUE", "Gini-Simpson Variance",
        "Hill (q=1)", "Renyi (q=3)", "HCq (q=4)", "HCq Variance (q=4)",
        "Mutation Frequency (dst)", "FAD", "Nucleotide Diversity (dst)",
        "Mutation Frequency (nm)", "Mutation Frequency Variance (nm)",
        "Nucleotide Diversity (dst, nr)", "Rao Pow (q=4)", "Rao Variance"
      ),
      Value = c(
        h_count, seg_sites, tot_muts,
        shannon_val, norm_shannon_val, shannon_var, norm_shannon_var,
        gini_simpson, gini_simpson_mvue, gini_simpson_var,
        hill_q1, renyi_q3, hcq_q4, hcq_var_q4,
        mut_freq_dst, fad_dst, as.numeric(nuc_div_dst),
        mut_freq_nm, mut_freq_var_nm,
        as.numeric(nuc_div_dst_nr), rao_pow_q4, as.numeric(rao_var)
      )
    )
    write.csv(summary_df, "diversity_indices_summary.csv", row.names = FALSE)
    
    # Save profiles to CSV
    write.csv(as.data.frame(hill_prof), "hill_profile.csv", row.names = FALSE)
    write.csv(as.data.frame(renyi_prof), "renyi_profile.csv", row.names = FALSE)
    write.csv(as.data.frame(hcq_prof), "hcq_profile.csv", row.names = FALSE)
    write.csv(as.data.frame(rao_prof), "rao_profile.csv", row.names = FALSE)
    
    # Save profiles to PDF plots
    pdf("diversity_profiles.pdf", width = 10, height = 8)
    par(mfrow = c(2, 2))
    plot(hill_prof\$q, hill_prof\$qD, type = "b", xlab = "q", ylab = "Hill number", main = "Hill Profile")
    plot(renyi_prof\$q, renyi_prof\$renyi, type = "b", xlab = "q", ylab = "Renyi entropy", main = "Renyi Profile")
    plot(hcq_prof\$q, hcq_prof\$HC, type = "b", xlab = "q", ylab = "HCq entropy", main = "HCq Profile")
    plot(rao_prof\$q, rao_prof\$qQ, type = "b", xlab = "q", ylab = "Rao entropy", main = "Rao Profile")
    dev.off()
    
    # Save R objects for downstream analysis
    saveRDS(lst, "quasispecies_data.rds")
    saveRDS(dst, "genetic_distances.rds")

    writeLines(c(
        '"BIOC_QSUTILS_COMPLEXITY_AND_DIVERSITY_ANALYSIS":',
        paste0('    QSutils: ', as.character(packageVersion('QSutils')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complexity_and_diversity_analysis.csv versions.yml
    """
}

workflow BIOC_QSUTILS_COMPLEXITY_AND_DIVERSITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ToyData_10_50_1000.fna ] ]

    main:
    BIOC_QSUTILS_COMPLEXITY_AND_DIVERSITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_QSUTILS_COMPLEXITY_AND_DIVERSITY_ANALYSIS.out.tables
    plots    = BIOC_QSUTILS_COMPLEXITY_AND_DIVERSITY_ANALYSIS.out.plots
    objects  = BIOC_QSUTILS_COMPLEXITY_AND_DIVERSITY_ANALYSIS.out.objects
    versions = BIOC_QSUTILS_COMPLEXITY_AND_DIVERSITY_ANALYSIS.out.versions
}
