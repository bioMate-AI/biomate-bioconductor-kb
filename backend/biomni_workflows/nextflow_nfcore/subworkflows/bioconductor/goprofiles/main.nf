#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: goProfiles
// The package implements methods to compare lists of genes based on comparing the corresponding 'funct
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/goProfiles/inst/doc/goProfiles.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("goProfiles")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOPROFILES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-goprofiles"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-goprofiles:1.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-goprofiles:1.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_goprofiles_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_goprofiles_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_goprofiles_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Welsh)
    library(jsonlite)

    # --- Prostateids [] ---
    # Key functions: data
    require(goProfiles)
    data(prostateIds)
    # --- Basicprofilesmf [] ---
    # Key functions: basicProfile, mergeProfilesLists, printProfiles
    welsh.MF <- basicProfile (welsh01EntrezIDs[1:100], onto="MF", level=2, orgPackage="org.Hs.eg.db")
    singh.MF <- basicProfile (singh01EntrezIDs[1:100], onto="MF", level=2, orgPackage="org.Hs.eg.db")
    welsh.singh.MF <-mergeProfilesLists(welsh.MF, singh.MF, profNames=c("Welsh", "Singh"))
    printProfiles(welsh.singh.MF, percentage=TRUE)
    # --- Plotprofilemf [] ---
    # Key functions: plotProfiles, Welsh
    plotProfiles (welsh.MF, aTitle="Welsh (2001). Prostate cancer data")
    # --- Basicprofilesany [] ---
    # Key functions: basicProfile
    welsh <- basicProfile (welsh01EntrezIDs[1:100], onto="ANY", level=2, orgPackage="org.Hs.eg.db")
    # --- Comparevisual [] ---
    # Key functions: plotProfiles
    plotProfiles (welsh.singh.MF, percentage=T,aTitle="Welsh vs Singh", legend=T)
    # --- Comparediff1 [] ---
    # Key functions: compareGeneLists, compSummary
    compared.welsh.singh.01.MF <- compareGeneLists (welsh01EntrezIDs[1:100], singh01EntrezIDs[1:100], onto="MF", level=2, orgPackage="org.Hs.eg.db")
    print(compSummary(compared.welsh.singh.01.MF))
    # --- Fishergoprof1 [] ---
    # Key functions: basicProfile, intersect, fisherGOProfiles
    list1 <- welsh01EntrezIDs[1:100]
    list2 <- singh01EntrezIDs[1:100]
    commProf <- basicProfile(intersect(list1, list2), onto="MF", level=2, orgPackage="org.Hs.eg.db")$MF
    fisherGOProfiles(welsh.MF$MF, singh.MF$MF, commProf, method="holm")
    # --- Compareequiv1 [] ---
    # Key functions: expandedProfile, intersect, equivalentGOProfiles, equivSummary
    data(prostateIds)
    expandedWelsh <- expandedProfile(welsh01EntrezIDs[1:100], onto="MF",
                            level=2, orgPackage="org.Hs.eg.db")
    expandedSingh <- expandedProfile(singh01EntrezIDs[1:100], onto="MF",
                            level=2, orgPackage="org.Hs.eg.db")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_goprofiles_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_goprofiles_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_goprofiles_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GOPROFILES:", paste0("    goprofiles: ", packageVersion("goProfiles"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_goprofiles_results.csv
    touch ${prefix}_goprofiles_output.rds
    echo "BIOC_GOPROFILES:" > versions.yml
    echo "    goprofiles: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GOPROFILES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GOPROFILES(ch_input)

    emit:
    results  = BIOC_GOPROFILES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GOPROFILES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GOPROFILES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GOPROFILES.out.versions  // channel: path(versions.yml)
}
