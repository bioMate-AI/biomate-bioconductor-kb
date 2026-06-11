# [biomate] structured fixture (rule: counts_coldata) — deterministic, no LLM
n_g<-200; n_s<-8; .m<-matrix(rpois(n_g*n_s,10),n_g,n_s,dimnames=list(paste0("g",1:n_g),paste0("s",1:n_s))); .cd<-S4Vectors::DataFrame(condition=factor(rep(c("A","B"),length.out=n_s)),row.names=colnames(.m))
write.csv(as.data.frame(.m), "matrix.csv", row.names=TRUE)
write.csv(as.data.frame(.cd), "coldata.csv", row.names=TRUE)
