#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SynMut — synonymous_mutation_design
// Design synonymously mutated DNA sequences with customized codon or dinucleotide usage patterns while preserving amino acid sequences and optional conserved regi
// Input: seqs.fasta, regions.csv
// Container: quay.io/biocontainers/bioconductor-synmut:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, SynMut
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import sequences and define mutable regions using input_seq to create a regioned_dna object
//  * 2. [Core Analysis] Retrieve baseline sequence properties (optional) using get_dna, get_region, get_cu, get_du, get_nu, get_freq, or get_rscu
//  * 3. [Core Analysis] Generate synonymous mutations using one of the mutation functions: codon_random (random mutations), codon_to (maximize/minimize sp
//  * 4. [Visualization & Output] Export the mutated DNA sequences using get_dna and Biostrings::writeXStringSet

nextflow.enable.dsl = 2

process BIOC_SYNMUT_SYNONYMOUS_MUTATION_DESIGN {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("SynMut", "Biostrings")
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
    library("SynMut")
    library("Biostrings")
    
    # Define input file paths
    filepath.fasta <- "seqs.fasta"
    filepath.csv <- "regions.csv"
    
    # Check if the required FASTA file exists
    if (!file.exists(filepath.fasta)) {
      stop("Error: Required input file 'seqs.fasta' not found in the working directory.")
    }
    
    # 1. Import sequences and define mutable regions
    if (file.exists(filepath.csv)) {
      message("Reading target regions from 'regions.csv'...")
      region <- read.csv(filepath.csv)
      rgd.seq <- input_seq(filepath.fasta, region)
    } else {
      message("No 'regions.csv' found. Importing sequences without predefined mutable regions...")
      rgd.seq <- input_seq(filepath.fasta)
    }
    
    # Display the regioned_dna object
    print(rgd.seq)
    
    # 2. Retrieve baseline sequence properties
    dna_seqs <- get_dna(rgd.seq)
    print(dna_seqs)
    
    # Access user-defined mutable regions
    regions_list <- get_region(rgd.seq)
    print(str(regions_list))
    
    # Get region of sequence without predefined regions for comparison
    print(get_region(input_seq(filepath.fasta)))
    
    # Retrieve codon, dinucleotide, and nucleotide usage
    baseline_cu <- get_cu(rgd.seq)
    baseline_du <- get_du(rgd.seq)
    baseline_nu <- get_nu(rgd.seq)
    
    # Save baseline properties to CSV
    write.csv(as.data.frame(baseline_cu), "baseline_codon_usage.csv", row.names = TRUE)
    write.csv(as.data.frame(baseline_du), "baseline_dinu_usage.csv", row.names = TRUE)
    write.csv(as.data.frame(baseline_nu), "baseline_nucleotide_usage.csv", row.names = TRUE)
    
    # 3. Generate synonymous mutations
    
    ## A. Random synonymous mutations
    message("Generating random synonymous mutations...")
    mut.seq_rand <- codon_random(rgd.seq)
    diff_cu_rand <- get_cu(mut.seq_rand) - get_cu(rgd.seq)
    write.csv(as.data.frame(diff_cu_rand), "diff_cu_random.csv")
    
    # Keeping the original codon usage pattern
    mut.seq_rand_keep <- codon_random(rgd.seq, keep = TRUE)
    diff_cu_rand_keep <- get_cu(mut.seq_rand_keep) - get_cu(rgd.seq)
    write.csv(as.data.frame(diff_cu_rand_keep), "diff_cu_random_keep.csv")
    
    # Mutating a specific proportion (50%) of codons
    mut.seq_rand_p50 <- codon_random(rgd.seq, n = 0.5)
    diff_cu_rand_p50 <- get_cu(mut.seq_rand_p50) - get_cu(rgd.seq)
    write.csv(as.data.frame(diff_cu_rand_p50), "diff_cu_random_p50.csv")
    Biostrings::writeXStringSet(get_dna(mut.seq_rand_p50), "mutated_random_p50.fasta")
    
    
    ## B. Synonymous mutants with maximal/minimal usage of specific codon
    message("Generating codon-targeted mutations (AAC)...")
    # Maximize AAC
    mut.seq_aac_max <- codon_to(rgd.seq, max.codon = "AAC")
    diff_cu_aac_max <- get_cu(mut.seq_aac_max) - get_cu(rgd.seq)
    write.csv(as.data.frame(diff_cu_aac_max), "diff_cu_aac_max.csv")
    Biostrings::writeXStringSet(get_dna(mut.seq_aac_max), "mutated_aac_max.fasta")
    
    # Minimize AAC
    mut.seq_aac_min <- codon_to(rgd.seq, min.codon = "AAC")
    diff_cu_aac_min <- get_cu(mut.seq_aac_min) - get_cu(rgd.seq)
    write.csv(as.data.frame(diff_cu_aac_min), "diff_cu_aac_min.csv")
    
    
    ## C. Synonymous mutants with maximal/minimal usage of specific dinucleotide
    message("Generating dinucleotide-targeted mutations...")
    # Maximize "cg"
    mut.seq_cg_max <- dinu_to(rgd.seq, max.dinu = "cg")
    diff_du_cg_max <- get_du(mut.seq_cg_max) - get_du(rgd.seq)
    write.csv(as.data.frame(diff_du_cg_max), "diff_du_cg_max.csv")
    Biostrings::writeXStringSet(get_dna(mut.seq_cg_max), "mutated_cg_max.fasta")
    
    # Minimize "CA"
    mut.seq_ca_min <- dinu_to(rgd.seq, min.dinu = "CA")
    diff_du_ca_min <- get_du(mut.seq_ca_min) - get_du(rgd.seq)
    write.csv(as.data.frame(diff_du_ca_min), "diff_du_ca_min.csv")
    
    # Maximize "cg" while keeping original codon usage
    mut.seq_cg_max_keep <- dinu_to(rgd.seq, max.dinu = "cg", keep = TRUE)
    diff_du_cg_max_keep <- get_du(mut.seq_cg_max_keep) - get_du(rgd.seq)
    diff_cu_cg_max_keep <- get_cu(mut.seq_cg_max_keep) - get_cu(rgd.seq)
    write.csv(as.data.frame(diff_du_cg_max_keep), "diff_du_cg_max_keep.csv")
    write.csv(as.data.frame(diff_cu_cg_max_keep), "diff_cu_cg_max_keep.csv")
    
    
    ## D. Synonymous mutants mimicking a specific codon usage pattern
    message("Generating codon-mimicking mutations...")
    # Use a codon usage vector as a target (safely handling single vs multiple sequences)
    cu_profile <- get_cu(rgd.seq)
    if (is.matrix(cu_profile) && nrow(cu_profile) >= 2) {
      target_vector <- cu_profile[2, ]
    } else if (is.matrix(cu_profile)) {
      target_vector <- cu_profile[1, ]
    } else {
      target_vector <- cu_profile
    }
    
    mut.seq_mimic_vec <- codon_mimic(rgd.seq, alt = target_vector)
    diff_cu_mimic_vec <- get_cu(mut.seq_mimic_vec) - get_cu(rgd.seq)
    write.csv(as.data.frame(diff_cu_mimic_vec), "diff_cu_mimic_vector.csv")
    
    # Use a sequence as a target
    target_seq <- Biostrings::DNAStringSet("TTGAAAA-CTC-N--AAG")
    mut.seq_mimic_seq <- codon_mimic(rgd.seq, alt = target_seq)
    
    diff_cu_mimic_seq <- get_cu(mut.seq_mimic_seq) - get_cu(rgd.seq)
    diff_freq_mimic_seq <- get_freq(mut.seq_mimic_seq) - get_freq(rgd.seq)
    diff_rscu_mimic_seq <- get_rscu(mut.seq_mimic_seq) - get_rscu(rgd.seq)
    
    write.csv(as.data.frame(diff_cu_mimic_seq), "diff_cu_mimic_seq.csv")
    write.csv(as.data.frame(diff_freq_mimic_seq), "diff_freq_mimic_seq.csv")
    write.csv(as.data.frame(diff_rscu_mimic_seq), "diff_rscu_mimic_seq.csv")
    Biostrings::writeXStringSet(get_dna(mut.seq_mimic_seq), "mutated_mimic_seq.fasta")
    
    
    # 4. Export the original regioned DNA sequences
    message("Exporting original regioned sequences...")
    Biostrings::writeXStringSet(get_dna(rgd.seq), "rgd.fasta")
    
    message("Pipeline completed successfully. Outputs generated in the working directory.")
    sessionInfo()

    writeLines(c(
        '"BIOC_SYNMUT_SYNONYMOUS_MUTATION_DESIGN":',
        paste0('    SynMut: ', as.character(packageVersion('SynMut')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synonymous_mutation_design.csv versions.yml
    """
}

workflow BIOC_SYNMUT_SYNONYMOUS_MUTATION_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seqs.fasta, regions.csv ] ]

    main:
    BIOC_SYNMUT_SYNONYMOUS_MUTATION_DESIGN(ch_input)

    emit:
    tables   = BIOC_SYNMUT_SYNONYMOUS_MUTATION_DESIGN.out.tables
    plots    = BIOC_SYNMUT_SYNONYMOUS_MUTATION_DESIGN.out.plots
    objects  = BIOC_SYNMUT_SYNONYMOUS_MUTATION_DESIGN.out.objects
    versions = BIOC_SYNMUT_SYNONYMOUS_MUTATION_DESIGN.out.versions
}
