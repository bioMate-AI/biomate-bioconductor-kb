#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qsutils — quasispecies_diversity_analysis
// Compute incidence-based, abundance-based, and functional diversity indices to characterize quasispecies complexity, with sample size correction.
// Input: ToyData_10_50_1000.fna
// Container: quay.io/biocontainers/bioconductor-qsutils:1.28.0--r45hdfd78af_0
// R packages: Biostrings, QSutils, ape
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QSUTILS_QUASISPECIES_DIVERSITY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-qsutils:1.28.0--r45hdfd78af_0"

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
    .bm_deps <- c("Biostrings", "QSutils", "ape")
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
    library(Biostrings)
    library(ape)
    library(QSutils)
    
    # Define input file path (must be in the working directory as specified)
    filepath <- "ToyData_10_50_1000.fna"
    
    if (!file.exists(filepath)) {
      stop(paste("Required input file missing:", filepath))
    }
    
    # 1. Load quasispecies data using ReadAmplSeqs
    lst <- ReadAmplSeqs(filepath, type="DNA")
    
    # 2. Compute incidence-based indices
    hseqs_len <- length(lst\$hseqs)
    seg_sites <- SegSites(lst\$hseqs)
    total_muts <- TotalMutations(lst\$hseqs)
    
    # 3. Compute abundance-based indices
    shannon_val <- Shannon(lst\$nr)
    norm_shannon <- NormShannon(lst\$nr)
    shannon_var <- ShannonVar(lst\$nr)
    norm_shannon_var <- NormShannonVar(lst\$nr)
    gini_simpson <- GiniSimpson(lst\$nr)
    gini_simpson_mvue <- GiniSimpsonMVUE(lst\$nr)
    gini_simpson_var <- GiniSimpsonVar(lst\$nr)
    hill_val <- Hill(lst\$nr, q=1)
    hill_prof <- HillProfile(lst\$nr)
    renyi_val <- Renyi(lst\$nr, q=3)
    renyi_prof <- RenyiProfile(lst\$nr)
    hcq_val <- HCq(lst\$nr, q= 4)
    hcq_var <- HCqVar(lst\$nr, q= 4)
    hcq_prof <- HCqProfile(lst\$nr)
    
    # 4. Compute functional diversity indices using genetic distances
    dst <- DNA.dist(lst\$hseqs, model="raw")
    mut_freq_dst <- MutationFreq(dst)
    fad_dst <- FAD(dst)
    nuc_div_dst <- NucleotideDiversity(dst)
    
    # Pairwise alignment and mismatch computation
    nm <- nmismatch(pairwiseAlignment(lst\$hseqs, lst\$hseqs[1]))
    mut_freq_nm <- MutationFreq(nm=nm, nr=lst\$nr, len=width(lst\$hseqs)[1])
    mut_freq_var <- MutationFreqVar(nm, lst\$nr, len=width(lst\$hseqs)[1])
    nuc_div_weighted <- NucleotideDiversity(dst, lst\$nr)
    rao_pow_val <- RaoPow(dst, 4, lst\$nr)
    rao_var_val <- RaoVar(dst, lst\$nr)
    rao_pow_prof <- RaoPowProfile(dst, lst\$nr)
    
    # 5. Correct for sample size bias using DSFT
    dsft_val <- DSFT(lst\$nr, size=2000)
    
    # --- Save Results ---
    
    # Create a summary table of single-value diversity indices
    summary_df <- data.frame(
      Metric = c(
        "Number_of_Haplotypes",
        "Segregating_Sites",
        "Total_Mutations",
        "Shannon_Entropy",
        "Normalized_Shannon_Entropy",
        "Shannon_Variance",
        "Normalized_Shannon_Variance",
        "Gini_Simpson_Index",
        "Gini_Simpson_MVUE",
        "Gini_Simpson_Variance",
        "Hill_Number_q1",
        "Renyi_Entropy_q3",
        "Havrda_Charvat_q4",
        "Havrda_Charvat_q4_Variance",
        "Mutation_Frequency_Entity",
        "Functional_Attribute_Diversity",
        "Nucleotide_Diversity_Entity",
        "Mutation_Frequency_Molecule",
        "Mutation_Frequency_Variance",
        "Nucleotide_Diversity_Weighted",
        "Rao_Entropy_q4",
        "Rao_Variance"
      ),
      Value = c(
        hseqs_len,
        seg_sites,
        total_muts,
        shannon_val,
        norm_shannon,
        shannon_var,
        norm_shannon_var,
        gini_simpson,
        gini_simpson_mvue,
        gini_simpson_var,
        hill_val,
        renyi_val,
        hcq_val,
        hcq_var,
        mut_freq_dst,
        fad_dst,
        as.numeric(nuc_div_dst),
        mut_freq_nm,
        mut_freq_var,
        as.numeric(nuc_div_weighted),
        rao_pow_val,
        as.numeric(rao_var_val)
      )
    )
    
    write.csv(summary_df, "quasispecies_diversity_summary.csv", row.names=FALSE)
    
    # Save profiles
    write.csv(as.data.frame(hill_prof), "hill_profile.csv", row.names=FALSE)
    write.csv(as.data.frame(renyi_prof), "renyi_profile.csv", row.names=FALSE)
    write.csv(as.data.frame(hcq_prof), "hcq_profile.csv", row.names=FALSE)
    write.csv(as.data.frame(rao_pow_prof), "rao_profile.csv", row.names=FALSE)
    
    # Save DSFT sample size correction results
    dsft_df <- data.frame(
      Haplotype = names(lst\$nr),
      Original_Count = lst\$nr,
      Kept_After_DSFT_2000 = dsft_val
    )
    write.csv(dsft_df, "dsft_sample_size_correction.csv", row.names=FALSE)
    
    # Generate and save plots of the diversity profiles
    pdf("quasispecies_diversity_profiles.pdf", width=10, height=8)
    par(mfrow=c(2,2))
    plot(hill_prof, type="b", main="Hill Numbers Profile", xlab="q", ylab="qD", col="blue", pch=19)
    plot(renyi_prof, type="b", main="Rényi Entropy Profile", xlab="q", ylab="renyi", col="red", pch=19)
    plot(hcq_prof, type="b", main="Havrda-Charvat Entropy Profile", xlab="q", ylab="HC", col="green", pch=19)
    plot(rao_pow_prof, type="b", main="Rao Entropy Profile", xlab="q", ylab="qQ", col="purple", pch=19)
    dev.off()
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_QSUTILS_QUASISPECIES_DIVERSITY_ANALYSIS":
        qsutils: \$(Rscript -e 'cat(as.character(packageVersion("qsutils")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_quasispecies_diversity_analysis.csv versions.yml
    """
}

workflow BIOC_QSUTILS_QUASISPECIES_DIVERSITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ToyData_10_50_1000.fna ] ]

    main:
    BIOC_QSUTILS_QUASISPECIES_DIVERSITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_QSUTILS_QUASISPECIES_DIVERSITY_ANALYSIS.out.tables
    plots    = BIOC_QSUTILS_QUASISPECIES_DIVERSITY_ANALYSIS.out.plots
    objects  = BIOC_QSUTILS_QUASISPECIES_DIVERSITY_ANALYSIS.out.objects
    versions = BIOC_QSUTILS_QUASISPECIES_DIVERSITY_ANALYSIS.out.versions
}
