#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cageminer
// This package aims to integrate GWAS-derived SNPs and coexpression networks to mine candidate genes a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cageminer/inst/doc/cageminer.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cageminer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAGEMINER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cageminer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cageminer:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cageminer:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cageminer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cageminer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cageminer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cageminer)
    library(jsonlite)


    # --- Cit [] ---
    # Key functions: citation, rot
    print(citation('cageminer'), bibtex = TRUE)
    # GRanges of SNP positions
    data(snp_pos)
    snp_pos

    # GRanges of chromosome lengths
    data(chr_length) 
    chr_length

    # GRanges of gene coordinates
    data(gene_ranges)

    # --- Snp Dist [] ---
    # Key functions: plot_snp_distribution, plot_snp_circos
    plot_snp_distribution(snp_pos)
    plot_snp_circos(chr_length, gene_ranges, snp_pos)

    # --- Multiple Traits [] ---
    # Key functions: GRangesList, sample, plot_snp_distribution, plot_snp_circos
    # Simulate multiple traits by sampling 20 SNPs 4 times
    snp_list <- GenomicRanges::GRangesList(
      Trait1 = sample(snp_pos, 20),
      Trait2 = sample(snp_pos, 20),
      Trait3 = sample(snp_pos, 20),
      Trait4 = sample(snp_pos, 20)
    )

    # Visualize SNP distribution across chromosomes
    plot_snp_distribution(snp_list)
    # Visualize SNP positions in the genome as a circos plot
    plot_snp_circos(chr_length, gene_ranges, snp_list)

    # --- Step By Step [] ---
    # Key functions: mine_step1, simulate_windows
    candidates1 <- mine_step1(gene_ranges, snp_pos)
    candidates1
    length(candidates1)
    # Single trait
    simulate_windows(gene_ranges, snp_pos)

    # Multiple traits
    simulate_windows(gene_ranges, snp_list)

    # --- Step2 [] ---
    # Key functions: SFT_fit, exp2gcn, mine_step2, signed, pearson, mine_step3, PRR_stress
    # Load guide genes
    data(guides)
    head(guides)

    # Infer GCN
    sft <- BioNERO::SFT_fit(pepper_se, net_type = "signed", cor_method = "pearson")
    gcn <- BioNERO::exp2gcn(pepper_se, net_type = "signed", cor_method = "pearson",
                            module_merging_threshold = 0.8, SFTpower = sft$power)

    # Apply step 2
    # See the levels from the sample metadata
    unique(pepper_se$Condition)

    # Apply step 3 using "PRR_stress" as the condition of interest
    candidates3 <- mine_step3(pepper_se, candidates = candidates2$candidates,
                              sample_group = "PRR_stress")
    candidates3

    # --- Mine Candidates [] ---
    # Key functions: mine_candidates, PRR_stress, get_hubs_gcn, score_genes
    candidates <- mine_candidates(gene_ranges = gene_ranges, 
                                  marker_ranges = snp_pos, 
                                  exp = pepper_se,
                                  gcn = gcn, guides = guides$Gene,
                                  sample_group = "PRR_stress")
    candidates
    # Load TFs
    data(tfs)
    head(tfs)

    # Get GCN hubs
    hubs <- BioNERO::get_hubs_gcn(pepper_se, gcn)
    head(hubs)

    # Score candidates
    scored <- score_genes(candidates, hubs$Gene, tfs$Gene_ID)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cageminer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cageminer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cageminer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CAGEMINER:", paste0("    cageminer: ", packageVersion("cageminer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cageminer_results.csv
    touch ${prefix}_cageminer_output.rds
    echo "BIOC_CAGEMINER:" > versions.yml
    echo "    cageminer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CAGEMINER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CAGEMINER(ch_input)

    emit:
    results  = BIOC_CAGEMINER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CAGEMINER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CAGEMINER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CAGEMINER.out.versions  // channel: path(versions.yml)
}
