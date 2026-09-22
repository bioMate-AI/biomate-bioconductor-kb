# BioMate OpenFE RBFE — Nextflow container (alias)
#
# The CANONICAL OpenFE RBFE image is built from backend/docker/openfe-rbfe/,
# tagged  399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/openfe-rbfe:1.0,
# and wired into:
#   * rebuild-base-and-cascade.sh  [4/8] openfe-rbfe
#   * the openfe_rbfe workflow's ECR container switch (main.nf / nextflow.config)
#
# This openfe-nf/ target exists only as the "…-nf" naming alias requested for
# the Nextflow subworkflow. To avoid a second divergent build of the same
# heavy scientific stack, it simply re-tags the canonical image. Build the
# canonical one first (backend/docker/openfe-rbfe/Dockerfile).
#
# Build:
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/openfe-nf:1.0 \
#     --push -f backend/docker/openfe-nf/Dockerfile .

FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/openfe-rbfe:1.0

LABEL maintainer="BioMate Team"
LABEL description="Alias of biomate/openfe-rbfe:1.0 (OpenFE RBFE for the openfe_rbfe Nextflow subworkflow)"

CMD ["python3", "-c", "import openfe; print('OpenFE', openfe.__version__, 'ready (openfe-nf alias)')"]
