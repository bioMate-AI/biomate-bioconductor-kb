#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiCDCPlus
// Systematic 3D interaction calls and differential analysis for Hi-C and HiChIP. The HiC-DC+ (Hi-C/HiC
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiCDCPlus/inst/doc/HiCDCPlus.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HiCDCPlus")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICDCPLUS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hicdcplus"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hicdcplus:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hicdcplus:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hicdcplus_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hicdcplus_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hicdcplus_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HiCDCPlus)
    library(jsonlite)

    # --- quickStart sig 2 [] ---
    # Key functions: user_cache_dir
    cache <- rappdirs::user_cache_dir(appname="HiCDCPlus")
    print(cache)
    # --- quickStart sig1 [] ---
    # Key functions: tempdir, construct_features
    hicfile_path<-system.file("extdata", "GSE63525_HMEC_combined_example.hic", package = "HiCDCPlus")
    outdir<-tempdir(check=TRUE)
    # --- quickStart sig2 [] ---
    # Key functions: generate_bintolen_gi_list, add_hic_counts
    gi_list<-generate_bintolen_gi_list(
    bintolen_path=paste0(outdir,"/hg19_50kb_GATC_bintolen.txt.gz"))
    gi_list<-add_hic_counts(gi_list,hic_path = hicfile_path)
    # --- quickStart sig3 [] ---
    # Key functions: expand_1D_features, HiCDCPlus, hicdc2hic, gi_list_write
    gi_list<-expand_1D_features(gi_list)
    set.seed(1010) #HiC-DC downsamples rows for modeling
    gi_list<-HiCDCPlus(gi_list) #HiCDCPlus_parallel runs in parallel across ncores
    # --- quickStart diff1 [] ---
    # Key functions: construct_features, generate_bintolen_gi_list, add_hic_counts, expand_1D_features
    construct_features(output_path=paste0(outdir,"/hg38_50kb_GATC"),
    chrs=c("chr22"))
    # --- quickStart diff2 [] ---
    # Key functions: hicdcdiff
    Differential analysis using modified DESeq2 (see ?hicdcdiff)
    # --- quickStart ice1 [] ---
    # Key functions: generate_binned_gi_list, add_hicpro_matrix_counts
    gi_list<-generate_binned_gi_list(50000,chrs=c("chr21","chr22"))
    gi_list<-add_hicpro_matrix_counts(gi_list,absfile_path,matrixfile_path,chrs=c("chr21","chr22")) #add paths to iced absfile and matrix files here
    # --- quickStart ice3 [] ---
    # Key functions: gi_list_topdom
    tads<-gi_list_topdom(gi_list,chrs=c("chr22"),window.size = 10)
    # --- quickStart comp1 [] ---
    # Key functions: extract_hic_eigenvectors

    # --- construct_features [] ---
    # Key functions: construct_features
    construct_features(output_path=paste0(outdir,"/hg19_50kb_GATC"),
    sig=c("GATC","GANTC"),bin_type="Bins-uniform",
    chrs=c("chr22"))
    # --- gi list uniform [] ---
    # Key functions: generate_binned_gi_list

    # --- gi list rebinned [] ---
    # Key functions: generate_df_gi_list
    df<-data.frame(chr='chr9',start=c(1,300,7867,103938))
    gi_list<-generate_df_gi_list(df)
    # --- gi list bintolen [] ---
    # Key functions: construct_features, generate_bintolen_gi_list
    construct_features(output_path=paste0(outdir,"/hg19_50kb_GATC"),
    chrs=c("chr22"))
    # --- custom features 2D [] ---
    # Key functions: generate_df_gi_list
    df<-data.frame(chr='chr9',start=seq(1e6,10e6,1e6))
    gi_list<-generate_df_gi_list(df,Dthreshold=500e3,chrs="chr9")
    # --- custom features 1D [] ---
    # Key functions: generate_df_gi_list, add_1D_features
    df<-data.frame(chr='chr9',start=seq(1e6,10e6,1e6),end=seq(2e6,11e6,1e6))
    gi_list<-generate_df_gi_list(df)
    feats<-data.frame(chr='chr9',start=seq(1e6,10e6,1e6),gc=runif(10))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hicdcplus_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hicdcplus_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hicdcplus_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICDCPLUS:", paste0("    hicdcplus: ", packageVersion("HiCDCPlus"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicdcplus_results.csv
    touch ${prefix}_hicdcplus_output.rds
    echo "BIOC_HICDCPLUS:" > versions.yml
    echo "    hicdcplus: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICDCPLUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICDCPLUS(ch_input)

    emit:
    results  = BIOC_HICDCPLUS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICDCPLUS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICDCPLUS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICDCPLUS.out.versions  // channel: path(versions.yml)
}
