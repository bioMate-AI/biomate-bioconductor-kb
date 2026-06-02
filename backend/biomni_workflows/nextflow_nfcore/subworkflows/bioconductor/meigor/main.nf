#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MEIGOR
// MEIGOR provides a comprehensive environment for performing global optimization tasks in bioinformati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MEIGOR/inst/doc/MEIGOR-vignette.R
// Upstream  : CNORode, CellNOptR
// Downstream: none
//
// Install: BiocManager::install("MEIGOR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEIGOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-meigor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-meigor:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-meigor:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_meigor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_meigor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_meigor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MEIGOR)
    library(jsonlite)


    # --- Quick Problem Solve [] ---
    # Key functions: function, constraints, rep, ex3, MEIGO, ex1

    # --- Ex2solve [] ---
    # Key functions: rep, MEIGO, ex2, function, ex3, ex4
    #=========================
    #PROBLEM SPECIFICATIONS
    #=========================
    problem<-list(f="ex2",x_L=rep(0,2),x_U=c(3,4),
    c_L=rep(-Inf,2), c_U=c(2,36))
    opts<-list(maxeval=750, local_solver="DHC", local_n1=2, local_n2=3)
    #=============================
    #END OF PROBLEM SPECIFICATIONS
    # ============================
    Results<-MEIGO(problem,opts,algorithm="ESS")
    # --- Source Rosen10 [] ---
    # Key functions: function, for, rep, rosen10, MEIGO
    rosen10<-function(x){
    		f<-0
    		n=length(x)
    		for (i in 1:(n-1)){
    			f <- f + 100*(x[i]^2 - x[i+1])^2 + (x[i]-1)^2
    		}
    		return(f)
    	}

    nvar<-10
    problem<-list(f="rosen10", x_L=rep(-5,nvar), x_U=rep(1,nvar))
    algorithm="VNS"
    opts<-list(maxeval=2000, maxtime=3600*69, use_local=1,
    	 aggr=0, local_search_type=1, decomp=1, maxdist=0.5)
    Results<-MEIGO(problem,opts,algorithm)

    # --- Ce Ssexample [] ---
    # Key functions: function, for, rep, methods, MEIGO, dhc, plotCNOlist, plotModel
    rosen10<-function(x){
    	f<-0
    	n=length(x)
    	for (i in 1:(n-1)){
    		 f <- f + 100*(x[i]^2 - x[i+1])^2 + (x[i]-1)^2
    	}
    	return(f)
    }

    nvar=20
    rosen10<-function(x){
    		f<-0
    		n=length(x)
    		for (i in 1:(n-1)){
    			f <- f + 100*(x[i]^2 - x[i+1])^2 + (x[i]-1)^2
    		}
    		return(f)
    	}

    nvar=20

    # --- Cnorode Example Pptimize [] ---
    # Key functions: getLBodeContObjFunction, MEIGO, plotLBodeFitness
    f_hepato<-getLBodeContObjFunction(cnolist, model, initial_pars, indices=NULL,
     time = 1, verbose = 0, transfer_function = 3, reltol = 1e-04, atol = 1e-03,
    maxStepSize =Inf, maxNumSteps = 1e4, maxErrTestsFails = 50, nan_fac = 5)
    n_pars=length(initial_pars$LB)
    problem<-list(f=f_hepato, x_L=initial_pars$LB[initial_pars$index_opt_pars],
    	x_U=initial_pars$UB[initial_pars$index_opt_pars],x_0=initial_pars$LB[initial_pars$index_opt_pars])
    opts<-list(maxeval=100, local_solver=0,ndiverse=10,dim_refset=6)
    Results<-MEIGO(problem,opts,algorithm="ESS")
    opt_pars=initial_pars;
    opt_pars$parValues=Results$xbest;
    simData=plotLBodeFitness(cnolist, model,opt_pars,
    	reltol = 1e-05, atol = 1e-03, maxStepSize = 0.01)

    # --- Cell Nopt Rexample Cnolist [] ---
    # Key functions: CNOlist, plotCNOlist, CellNOptR_example, preprocessing, plotModel, function, prep4sim, computeScoreT1
    library(MEIGOR)
    library(CellNOptR)
    data("CellNOptR_example",package="MEIGOR")
    cnolist=CNOlist(cnolist_cellnopt)
    plotCNOlist(cnolist)
    model <- preprocessing(cnolist, model_cellnopt, expansion=TRUE, compression=TRUE, verbose=FALSE)
    plotModel(model, cnolist)
    get_fobj<- function(cnolist,model){

    	f<-function(x,model1=model,cnolist1=cnolist){
    		simlist=prep4sim(model1)
    		score=computeScoreT1(cnolist1, model1, x)
    		return(score)
    	}
    }
    fobj=get_fobj(cnolist,model)
    nvar=16

    problem<-list(f=fobj, x_L=rep(0,nvar), x_U=rep(1,nvar))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_meigor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_meigor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_meigor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MEIGOR:", paste0("    meigor: ", packageVersion("MEIGOR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meigor_results.csv
    touch ${prefix}_meigor_output.rds
    echo "BIOC_MEIGOR:" > versions.yml
    echo "    meigor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MEIGOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MEIGOR(ch_input)

    emit:
    results  = BIOC_MEIGOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MEIGOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MEIGOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MEIGOR.out.versions  // channel: path(versions.yml)
}
