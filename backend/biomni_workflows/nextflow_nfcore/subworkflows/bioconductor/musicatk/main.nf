#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: musicatk — de_novo_signature_discovery
// Extract variants from VCF/MAF files, build standard mutation count tables, discover novel mutational signatures and exposures de novo, and perform downstream vi
// Input: public_TCGA.LUSC.maf, public_LUAD_TCGA-97-7938.vcf, sample_annotations.txt
// Container: quay.io/biocontainers/bioconductor-musicatk:2.4.0--r45h1f0d9b5_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUSICATK_DE_NOVO_SIGNATURE_DISCOVERY {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-musicatk:2.4.0--r45h1f0d9b5_0"

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
    .bm_deps <- c("musicatk")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(musicatk)
    
    # Set seed for reproducibility of stochastic algorithms (NMF, UMAP)
    set.seed(1)
    
    # Define input file paths from the working directory
    lusc_maf <- "public_TCGA.LUSC.maf"
    luad_vcf <- "public_LUAD_TCGA-97-7938.vcf"
    sample_annotations_file <- "sample_annotations.txt"
    
    # 1. Extract variants from files
    lusc.variants <- extract_variants_from_maf_file(maf_file = lusc_maf)
    luad.variants <- extract_variants_from_vcf_file(vcf_file = luad_vcf)
    variants <- extract_variants(c(lusc_maf, luad_vcf))
    
    # 2. Select reference genome
    g <- select_genome("hg38")
    
    # 3. Create a musica object
    musica <- create_musica_from_variants(x = variants, genome = g)
    
    # 4. Build standard mutation count tables
    build_standard_table(musica, g = g, table_name = "SBS96")
    
    # 5. Determine optimal signature count (k)
    k_comparison <- compare_k_vals(musica, "SBS96",
      reps = 5, min_k = 2, max_k = 4,
      algorithm = "nmf"
    )
    saveRDS(k_comparison, "k_comparison.rds")
    
    # 6. Discover signatures and exposures de novo
    discover_signatures(
      musica = musica, modality = "SBS96", num_signatures = 3,
      algorithm = "nmf", model_id = "ex_result", nstart = 10
    )
    
    # 7. Extract exposures and signatures
    expos <- exposures(musica, "result", "SBS96", "ex_result")
    sigs <- signatures(musica, "result", "SBS96", "ex_result")
    
    # Write extracted matrices to CSV
    write.csv(expos, "exposures.csv", row.names = TRUE)
    write.csv(sigs, "signatures.csv", row.names = TRUE)
    
    # Plot and save initial signatures
    pdf("signatures_plot.pdf", width = 10, height = 6)
    plot_signatures(musica, model_id = "ex_result", modality = "SBS96")
    dev.off()
    
    # Rename signatures and plot again
    name_signatures(musica, "ex_result", c("Smoking", "APOBEC", "UV"))
    
    pdf("signatures_named_plot.pdf", width = 10, height = 6)
    plot_signatures(musica, model_id = "ex_result", modality = "SBS96")
    dev.off()
    
    # Plot and save exposures
    pdf("exposures_plot.pdf", width = 10, height = 6)
    plot_exposures(musica, "ex_result", plot_type = "bar")
    dev.off()
    
    # 8. Annotate samples using sample metadata
    annot <- read.table(sample_annotations_file, sep = "\t", header = TRUE)
    samp_annot(musica, "Tumor_Subtypes") <- annot\$Tumor_Subtypes
    
    # 9. Visualize exposures grouped by annotation
    pdf("exposures_by_subtype_plot.pdf", width = 10, height = 6)
    plot_exposures(musica, "ex_result",
      plot_type = "bar", group_by = "annotation",
      annotation = "Tumor_Subtypes"
    )
    dev.off()
    
    # Visualize samples in 2D using UMAP (wrapped in tryCatch in case of low sample size)
    tryCatch({
      create_umap(musica, "ex_result")
      
      pdf("umap_plot.pdf", width = 8, height = 6)
      plot_umap(musica, "ex_result")
      dev.off()
    }, error = function(e) {
      message("UMAP generation skipped or failed: ", e\$message)
    })
    
    # Save the final musica object
    saveRDS(musica, "musica_object.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MUSICATK_DE_NOVO_SIGNATURE_DISCOVERY":
        musicatk: \$(Rscript -e 'cat(as.character(packageVersion("musicatk")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_de_novo_signature_discovery.csv versions.yml
    """
}

workflow BIOC_MUSICATK_DE_NOVO_SIGNATURE_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ public_TCGA.LUSC.maf, public_LUAD_TCGA-97-7938.vcf, sample_annotations.txt ] ]

    main:
    BIOC_MUSICATK_DE_NOVO_SIGNATURE_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_MUSICATK_DE_NOVO_SIGNATURE_DISCOVERY.out.tables
    plots    = BIOC_MUSICATK_DE_NOVO_SIGNATURE_DISCOVERY.out.plots
    objects  = BIOC_MUSICATK_DE_NOVO_SIGNATURE_DISCOVERY.out.objects
    versions = BIOC_MUSICATK_DE_NOVO_SIGNATURE_DISCOVERY.out.versions
}
