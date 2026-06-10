#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qsutils — genotyping_unknown_haplotypes
// Classify an unknown target haplotype into a genotype using reference standards and distance-based discriminant rules.
// Input: Unknown-Genotype.fna, GenotypeStandards_A-H.fas
// Container: quay.io/biocontainers/bioconductor-qsutils:1.28.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QSUTILS_GENOTYPING_UNKNOWN_HAPLOTYPES {
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
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(QSutils)
    library(ape)
    library(Biostrings)
    
    # Define input file paths as specified by the user
    target_filepath <- "Unknown-Genotype.fna"
    refs_filepath <- "GenotypeStandards_A-H.fas"
    
    # Verify input files exist
    if (!file.exists(target_filepath)) {
      stop(paste("Required input file missing:", target_filepath))
    }
    if (!file.exists(refs_filepath)) {
      stop(paste("Required input file missing:", refs_filepath))
    }
    
    # 1. Load target sequence and reference sequences using ReadAmplSeqs
    # (Adapting the documented code to use the local user input files)
    filepath <- target_filepath
    lst2Geno <- ReadAmplSeqs(filepath, type = "DNA")
    hseq <- lst2Geno\$hseq[1]
    # Fallback in case of list element naming discrepancy in the package
    if (is.null(hseq)) {
      hseq <- lst2Geno\$hseqs[1]
    }
    
    filepath <- refs_filepath
    lstRefs <- ReadAmplSeqs(filepath, type = "DNA")
    RefSeqs <- lstRefs\$hseq
    # Fallback in case of list element naming discrepancy in the package
    if (is.null(RefSeqs)) {
      RefSeqs <- lstRefs\$hseqs
    }
    
    # 2. Compute distance matrix using DNA.dist from ape
    dm <- as.matrix(DNA.dist(c(hseq, RefSeqs), model = "K80"))
    
    # 3. Extract distances between references and from target to references
    dgrp <- dm[-1, -1]
    d <- dm[1, -1]
    grp <- factor(substr(rownames(dgrp), 1, 1))
    hr <- as.integer(grp)
    
    # 4. Classify the target sequence using DBrule
    dsc <- DBrule(dgrp, hr, d, levels(grp))
    
    # Save meaningful results to output files
    # Save the raw dsc object
    saveRDS(dsc, file = "genotyping_results.rds")
    
    # Save a summary table of the classification
    phi2_names <- names(dsc\$Phi2)
    genotypes <- sub("Phi2\\.", "", phi2_names)
    results_df <- data.frame(
      Genotype = genotypes,
      Phi2_Score = as.numeric(dsc\$Phi2),
      Is_Predicted_Genotype = ifelse(genotypes == dsc\$Type, TRUE, FALSE)
    )
    write.csv(results_df, file = "genotyping_results.csv", row.names = FALSE)
    
    # Generate a PDF plot of the discriminant scores
    pdf("genotyping_phi2_plot.pdf", width = 8, height = 6)
    colors <- ifelse(genotypes == dsc\$Type, "forestgreen", "skyblue")
    barplot(
      dsc\$Phi2,
      names.arg = genotypes,
      col = colors,
      main = paste("Genotyping Results (Predicted Genotype:", dsc\$Type, ")"),
      xlab = "Genotype Standards",
      ylab = "Phi2 Distance Score (Lower is better)",
      las = 1
    )
    grid(nx = NA, ny = NULL)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_QSUTILS_GENOTYPING_UNKNOWN_HAPLOTYPES":
        qsutils: \$(Rscript -e 'cat(as.character(packageVersion("qsutils")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genotyping_unknown_haplotypes.csv versions.yml
    """
}

workflow BIOC_QSUTILS_GENOTYPING_UNKNOWN_HAPLOTYPES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Unknown-Genotype.fna, GenotypeStandards_A-H.fas ] ]

    main:
    BIOC_QSUTILS_GENOTYPING_UNKNOWN_HAPLOTYPES(ch_input)

    emit:
    tables   = BIOC_QSUTILS_GENOTYPING_UNKNOWN_HAPLOTYPES.out.tables
    plots    = BIOC_QSUTILS_GENOTYPING_UNKNOWN_HAPLOTYPES.out.plots
    objects  = BIOC_QSUTILS_GENOTYPING_UNKNOWN_HAPLOTYPES.out.objects
    versions = BIOC_QSUTILS_GENOTYPING_UNKNOWN_HAPLOTYPES.out.versions
}
