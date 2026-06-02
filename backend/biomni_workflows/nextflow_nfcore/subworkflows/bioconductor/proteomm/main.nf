#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ProteoMM
// ProteoMM is a statistical method to perform model-based peptide-level differential expression analys
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ProteoMM/inst/doc/ProteoMM_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ProteoMM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROTEOMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-proteomm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-proteomm:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-proteomm:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_proteomm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_proteomm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_proteomm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ProteoMM)
    library(jsonlite)


    # --- Results = False [] ---
    # Key functions: eig_norm1, eig_norm2, values
    hs_m_ints_eig1 = eig_norm1(m=m_logInts,treatment=grps,prot.info=m_prot.info)

    ## -----------------------------------------------------------------------------
    names(hs_m_ints_eig1)

    ## -----------------------------------------------------------------------------
    hs_m_ints_eig1$h.c
    hs_m_ints_norm_1bt = eig_norm2(rv=hs_m_ints_eig1) 

    ## -----------------------------------------------------------------------------
    names(hs_m_ints_eig1)
    # how many peptides with no missing values (complete) are in the data? 
    dim(hs_m_ints_eig1$complete)# bias trend identification is based on 196 peptides

    ## -----------------------------------------------------------------------------
    hs_m_ints_eig1$h.c = 2 # visually there are more than 1 bias trend, set to 2

    # --- Results = False [] ---
    # Key functions: eig_norm2
    hs_m_ints_norm = eig_norm2(rv=hs_m_ints_eig1)
    cat("\\newpage")

    # --- Results = False [] ---
    # Key functions: eig_norm1, eig_norm2
    mm_m_ints_eig1 = eig_norm1(m=m_logInts,treatment=grps,prot.info=m_prot.info)

    ## -----------------------------------------------------------------------------
    mm_m_ints_eig1$h.c
    mm_m_ints_norm_1bt = eig_norm2(rv=mm_m_ints_eig1) 

    ## -----------------------------------------------------------------------------
    mm_m_ints_eig1$h.c = 2

    # --- Results = False [] ---
    # Key functions: eig_norm2, trends
    mm_m_ints_norm = eig_norm2(rv=mm_m_ints_eig1)  
    # 190 petides with no missing values were used to id bais trends ($complete)

    ## -----------------------------------------------------------------------------
    length(mm_m_ints_eig1$prot.info$MatchedID)          # 1102 - correct
    length(hs_m_ints_eig1$prot.info$MatchedID)          # 695 - can normalize all
    length(unique(mm_m_ints_eig1$prot.info$MatchedID) ) # 69
    length(unique(hs_m_ints_eig1$prot.info$MatchedID) ) # 69

    # 787 peptides were normalized, rest eliminated due to low # of observations
    cat("\\newpage")

    ## -----------------------------------------------------------------------------
    hs_prot.info = hs_m_ints_norm$normalized[,metaCols]
    hs_norm_m =  hs_m_ints_norm$normalized[,intsCols]
    head(hs_prot.info)
    head(hs_norm_m)
    dim(hs_norm_m) # 480 x 6, raw: 695, 215 peptides were eliminated due to lack of 
                   # observations
    length(unique(hs_prot.info$MatchedID)) # 59

    # --- Warning=false [] ---
    # Key functions: MBimpute
    imp_hs = MBimpute(hs_norm_m, grps, prot.info=hs_prot.info, pr_ppos=3, 
                      my.pi=0.05, compute_pi=FALSE) # use default pi
    # historically pi=.05 has been representative of the % missing 
    # observations missing completely at random
    set.seed(12131) # set random number generator seed for reproducibility, 
    # otherwise will get various imputed values for repeated attempts
    # as for Human, impute based on ProtID - position in the matrix for the Protein Identifier 
    imp_mm = MBimpute(mm_norm_m, grps, prot.info=mm_prot.info, pr_ppos=3, 
                      my.pi=0.05, compute_pi=FALSE) 
                      # pi =.05 is usually a good estimate

    ## -----------------------------------------------------------------------------
    dim(imp_mm$imp_prot.info) # 787 x 7 - imputed peptides & 787 were normalized
    dim(imp_mm$y_imputed)     # 787 x 6

    # --- Results='asis' [] ---
    # Key functions: subset_proteins, prot_level_multi_part, values, par, p.adjust, plot_volcano_wLab
    cat("\\newpage")

    ## -----------------------------------------------------------------------------
    # make parallel lists to pass as parameters  
    mms = list()
    treats = list()
    protinfos = list()
    mms[[1]] = imp_mm$y_imputed
    mms[[2]] = imp_hs$y_imputed 
    treats[[1]] = grps
    ptm = proc.time()
    set.seed=(12357)
    comb_MBDE = prot_level_multi_part(mm_list=mms, treat=treats,prot.info=protinfos, 
                                      prot_col_name='ProtID', nperm=nperm, 
                                      dataset_suffix=c('MM', 'HS'))
    proc.time() - ptm  # shows how long it takes to run the test

    ## ----fig.cap="P-value distributions for unadjusted and adjusted p-values. Adjusted p-values (top right) look as expected according to the theory with a peak near 0 and an approximately uniform distribution throughout the interval [0 1]. Benjamini-Hochberg adjusted p-values (bottom left) do not look according to the theoretical distribution, thus Benjamini-Hochberg adjusted may not be appropriate."----
    mybreaks = seq(0,1, by=.05)
    # adjustment for permutation test is done by stretching out values on the

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_proteomm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_proteomm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_proteomm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROTEOMM:", paste0("    proteomm: ", packageVersion("ProteoMM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proteomm_results.csv
    touch ${prefix}_proteomm_output.rds
    echo "BIOC_PROTEOMM:" > versions.yml
    echo "    proteomm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROTEOMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROTEOMM(ch_input)

    emit:
    results  = BIOC_PROTEOMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROTEOMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROTEOMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROTEOMM.out.versions  // channel: path(versions.yml)
}
