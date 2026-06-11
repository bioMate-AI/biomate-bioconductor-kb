library(NormqPCR)
library(ReadqPCR)

# Find and copy qPCR.techReps.txt
f1 <- list.files(system.file("exData", package="NormqPCR"), pattern="qPCR.techReps.txt", full.names=TRUE)
if (length(f1) == 0) {
    f1 <- list.files(system.file("exData", package="ReadqPCR"), pattern="qPCR.techReps.txt", full.names=TRUE)
}
if (length(f1) > 0) {
    file.copy(f1[1], "qPCR.techReps.txt", overwrite=TRUE)
} else {
    # Fallback synthetic file
    write.table(
        data.frame(Well=c("A1","A2"), Sample=c("S1","S1"), Detector=c("D1","D1"), Cq=c(20.5, 20.6)), 
        "qPCR.techReps.txt", sep="\t", row.names=FALSE, quote=FALSE
    )
}

# Find and copy example.txt
f2 <- list.files(system.file("exData", package="NormqPCR"), pattern="example.txt", full.names=TRUE)
if (length(f2) == 0) {
    f2 <- list.files(system.file("exData", package="ReadqPCR"), pattern="example.txt", full.names=TRUE)
}
if (length(f2) > 0) {
    file.copy(f2[1], "example.txt", overwrite=TRUE)
} else {
    # Fallback synthetic file
    write.table(
        data.frame(Well=c("A1","A2"), Sample=c("S1","S1"), Detector=c("D1","D1"), Cq=c(20.5, 20.6)), 
        "example.txt", sep="\t", row.names=FALSE, quote=FALSE
    )
}