#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RVS
// Rare Variant Sharing (RVS) implements tests of association and linkage between rare genetic variant 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RVS/inst/doc/RVS.R
// Upstream  : kinship2, snpStats
// Downstream: none
//
// Install: BiocManager::install("RVS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RVS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rvs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rvs:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rvs:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rvs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rvs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rvs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ComputeKinshipPropCoef)
    library(RVgene)
    library(RVsharing)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data, rep
    ---------------------------------------------------------------------
    data(samplePedigrees)
    # store the pedigrees
    fam_type_A <- samplePedigrees$firstCousinPair
    fam_type_B <- samplePedigrees$secondCousinPair
    # --- Rvsharing [] ---
    # Key functions: RVsharing
    ---------------------------------------------------------------------
    p <- RVsharing(fam_type_D)
    # --- List [] ---
    # Key functions: RVsharing, signif, multipleFamilyPValue
    ---------------------------------------------------------------------
    # compute the sharing probabilities for all families
    fams <- list(fam_type_A, fam_type_B, fam_type_C, fam_type_D)
    sharing_probs <- suppressMessages(RVsharing(fams))
    signif(sharing_probs, 3)
    # --- Multiplevariantpvalue [] ---
    # Key functions: multipleVariantPValue, signif
    ---------------------------------------------------------------------
    result <- multipleVariantPValue(sample$genotypes, sample$fam, sharingProbs)
    signif(result$pvalues, 3)
    # --- Multiplevariantpvalue [] ---
    # Key functions: multipleVariantPValue
    ---------------------------------------------------------------------
    result <- multipleVariantPValue(sample$genotypes, sample$fam, sharingProbs, filter='bonferroni', alpha=0.05)
    # --- Seq [] ---
    # Key functions: RVsharing
    ---------------------------------------------------------------------
    # calculate p-values for each MAF
    freq <- seq(0,0.05,0.005)
    variants <- names(sort(result$pvalues))[1:3]
    pvals <- matrix(nrow=length(freq), ncol=length(variants))
    # --- Enrichmentpvalue [] ---
    # Key functions: enrichmentPValue
    ---------------------------------------------------------------------
    enrichmentPValue(sample$genotypes, sample$fam, sharingProbs, 0.001)
    # --- Rvsharing [] ---
    # Key functions: RVsharing
    ---------------------------------------------------------------------
    fam15157.pattern.prob = RVsharing(samplePedigrees$secondCousinTriple,splitPed=TRUE)
    # --- Data [] ---
    # Key functions: genotypeToSnpMatrix
    ---------------------------------------------------------------------
    data(famVCF)
    fam15157.snp = VariantAnnotation::genotypeToSnpMatrix(fam15157.vcf)
    fam28003.snp = VariantAnnotation::genotypeToSnpMatrix(fam28003.vcf)
    # --- Rvgene [] ---
    # Key functions: RVgene
    ---------------------------------------------------------------------
    RVgene(ex.SnpMatrix.list,ex.ped.obj,sites,pattern.prob.list=ex.pattern.prob.list,nequiv.list=ex.nequiv.list,N.list=ex.N.list,type="count")
    # --- Plot [] ---
    # Key functions: RVsharing
    ---------------------------------------------------------------------
    ped <- samplePedigrees$firstCousinTriple
    ped$affected[9] <- 0
    plot(ped)
    p <- RVsharing(ped)
    # --- Rvsharing [] ---
    # Key functions: RVsharing
    ---------------------------------------------------------------------
    p <- RVsharing(samplePedigrees$firstCousinPair, alleleFreq=0.01)
    p <- RVsharing(samplePedigrees$firstCousinPair, alleleFreq=0.01, nSim=1e5)
    # --- Function [] ---
    # Key functions: sample, RVsharing
    ---------------------------------------------------------------------
    # assumption that 1 founder introduces variant
    fDist <- function(N) sample(c(rep(0,N-1), 1))
    p <- RVsharing(samplePedigrees$firstCousinPair, nSim=1e5, founderDist=fDist)
    p <- RVsharing(samplePedigrees$firstCousinPair)
    # --- Plot [] ---
    # Key functions: ComputeKinshipPropCoef
    ---------------------------------------------------------------------
    plot(samplePedigrees$twoGenerationsInbreeding)
    ComputeKinshipPropCoef(samplePedigrees$twoGenerationsInbreeding)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rvs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rvs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rvs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RVS:", paste0("    rvs: ", packageVersion("RVS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rvs_results.csv
    touch ${prefix}_rvs_output.rds
    echo "BIOC_RVS:" > versions.yml
    echo "    rvs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RVS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RVS(ch_input)

    emit:
    results  = BIOC_RVS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RVS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RVS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RVS.out.versions  // channel: path(versions.yml)
}
