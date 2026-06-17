#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: somaticsignatures — somatic_signature_extraction
// Extract and analyze somatic mutational signatures from somatic SNV calls and a reference genome.
// Input: somatic_variants.vcf, reference_genome.fa
// Container: quay.io/biocontainers/bioconductor-somaticsignatures:2.46.0--r45hdfd78af_0
// R packages: Rsamtools, ggdendro, ggplot2, knitr, somaticcanceralterations, SomaticSignatures, VariantAnnotation
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SOMATICSIGNATURES_SOMATIC_SIGNATURE_EXTRACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-somaticsignatures:2.46.0--r45hdfd78af_0"

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
    .bm_deps <- c("Rsamtools", "ggdendro", "ggplot2", "knitr", "somaticcanceralterations", "SomaticSignatures", "VariantAnnotation")
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
    
    library(SomaticSignatures)
    library(VariantAnnotation)
    library(Rsamtools)
    library(ggplot2)
    
    # --- Import somatic variants into a VRanges object ---
    vcf_file <- "somatic_variants.vcf"
    vcf <- readVcf(vcf_file)
    sca_vr <- as(vcf, "VRanges")
    
    # Ensure we have a "study" column and at least 8 groups to support 2:8 signatures
    if (!"study" %in% colnames(mcols(sca_vr))) {
        sca_vr\$study <- factor(sampleNames(sca_vr))
    }
    if (length(unique(sca_vr\$study)) < 8) {
        sca_vr\$study <- factor(paste0("study", (seq_len(length(sca_vr)) %% 8) + 1))
    }
    
    # Load reference genome
    ref_file <- "reference_genome.fa"
    if (!file.exists(paste0(ref_file, ".fai"))) {
        indexFa(ref_file)
    }
    ref_genome <- FaFile(ref_file)
    
    # --- Extract the trinucleotide sequence context of each variant ---
    sca_motifs <- mutationContext(sca_vr, ref_genome)
    
    # --- Construct a normalized motif matrix grouped by study ---
    sca_mm <- motifMatrix(sca_motifs, group = "study", normalize = TRUE)
    
    # Save the mutation spectrum plot
    pdf("mutation_spectrum.pdf", width = 10, height = 6)
    p_spec <- plotMutationSpectrum(sca_motifs, "study")
    print(p_spec)
    dev.off()
    
    # --- Assess the optimal number of signatures ---
    n_sigs <- 2:8
    gof_nmf <- assessNumberSignatures(sca_mm, n_sigs, nReplicates = 5)
    gof_pca <- assessNumberSignatures(sca_mm, n_sigs, pcaDecomposition)
    
    pdf("number_signatures_assessment.pdf", width = 8, height = 6)
    p_gof_nmf <- plotNumberSignatures(gof_nmf)
    print(p_gof_nmf)
    p_gof_pca <- plotNumberSignatures(gof_pca)
    print(p_gof_pca)
    dev.off()
    
    # --- Identify mutational signatures using NMF and PCA ---
    n_sigs <- 5
    sigs_nmf <- identifySignatures(sca_mm, n_sigs, nmfDecomposition)
    sigs_pca <- identifySignatures(sca_mm, n_sigs, pcaDecomposition)
    
    # Save signature objects
    saveRDS(sigs_nmf, "sigs_nmf.rds")
    saveRDS(sigs_pca, "sigs_pca.rds")
    
    # --- Visualize the signatures, sample contributions, and ---
    pdf("somatic_signatures_nmf_plots.pdf", width = 10, height = 8)
    
    p1 <- plotSignatureMap(sigs_nmf) + ggtitle("Somatic Signatures: NMF - Heatmap")
    print(p1)
    
    p2 <- plotSignatures(sigs_nmf) + ggtitle("Somatic Signatures: NMF - Barchart")
    print(p2)
    
    p3 <- plotObservedSpectrum(sigs_nmf)
    print(p3)
    
    p4 <- plotFittedSpectrum(sigs_nmf)
    print(p4)
    
    p5 <- plotSampleMap(sigs_nmf)
    print(p5)
    
    p6 <- plotSamples(sigs_nmf)
    print(p6)
    
    dev.off()
    
    # --- Cluster the mutational spectrum by motif ---
    clu_motif <- clusterSpectrum(sca_mm, "motif")
    saveRDS(clu_motif, "cluster_motif.rds")
    
    # Write out the motif matrix as a CSV
    write.csv(sca_mm, "motif_matrix.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_SOMATICSIGNATURES_SOMATIC_SIGNATURE_EXTRACTION":',
        paste0('        somaticsignatures: ', as.character(packageVersion("somaticsignatures")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_somatic_signature_extraction.csv versions.yml
    """
}

workflow BIOC_SOMATICSIGNATURES_SOMATIC_SIGNATURE_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ somatic_variants.vcf, reference_genome.fa ] ]

    main:
    BIOC_SOMATICSIGNATURES_SOMATIC_SIGNATURE_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_SOMATICSIGNATURES_SOMATIC_SIGNATURE_EXTRACTION.out.tables
    plots    = BIOC_SOMATICSIGNATURES_SOMATIC_SIGNATURE_EXTRACTION.out.plots
    objects  = BIOC_SOMATICSIGNATURES_SOMATIC_SIGNATURE_EXTRACTION.out.objects
    versions = BIOC_SOMATICSIGNATURES_SOMATIC_SIGNATURE_EXTRACTION.out.versions
}
