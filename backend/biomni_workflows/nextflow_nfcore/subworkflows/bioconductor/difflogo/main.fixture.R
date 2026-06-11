library(DiffLogo)

# Locate the example PWM files shipped with the DiffLogo package
pwm_files <- list.files(system.file("extdata", package="DiffLogo"), pattern="\\.pwm$", recursive=TRUE, full.names=TRUE)

if (length(pwm_files) >= 2) {
    # Copy the first two shipped PWM files to the expected input filenames
    file.copy(pwm_files[1], "pwm1.pwm", overwrite = TRUE)
    file.copy(pwm_files[2], "pwm2.pwm", overwrite = TRUE)
} else {
    # Fallback: create synthetic PWM files if shipped files are not found
    pwm1 <- matrix(c(0.2, 0.2, 0.4, 0.2,
                     0.1, 0.1, 0.7, 0.1,
                     0.3, 0.3, 0.2, 0.2,
                     0.25, 0.25, 0.25, 0.25), 
                   nrow=4, dimnames=list(c("A","C","G","T"), NULL))
                   
    pwm2 <- matrix(c(0.25, 0.25, 0.25, 0.25,
                     0.4, 0.1, 0.1, 0.4,
                     0.2, 0.3, 0.3, 0.2,
                     0.1, 0.4, 0.4, 0.1), 
                   nrow=4, dimnames=list(c("A","C","G","T"), NULL))
                   
    write.table(pwm1, "pwm1.pwm", sep="\t", quote=FALSE, row.names=TRUE, col.names=FALSE)
    write.table(pwm2, "pwm2.pwm", sep="\t", quote=FALSE, row.names=TRUE, col.names=FALSE)
}