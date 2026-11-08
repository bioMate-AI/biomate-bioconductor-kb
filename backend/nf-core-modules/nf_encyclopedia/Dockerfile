ARG VERSION=1.12.34

FROM --platform=linux/amd64 mambaorg/micromamba:latest as micromamba
FROM --platform=linux/amd64 searlelab/encyclopedia:$VERSION
LABEL authors="wfondrie@talus.bio" \
      description="Docker image for most of nf-encyclopedia"

# Install procps so that Nextflow can poll CPU usage and
# deep clean the apt cache to reduce image/layer size
RUN apt-get update \
    && apt-get install -y procps sqlite3 \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Setup micromamba:
ARG MAMBA_USER=mamba
ARG MAMBA_USER_ID=1000
ARG MAMBA_USER_GID=1000
ENV MAMBA_USER=$MAMBA_USER
ENV MAMBA_ROOT_PREFIX="/opt/conda"
ENV MAMBA_EXE="/bin/micromamba"

COPY --from=micromamba "$MAMBA_EXE" "$MAMBA_EXE"
COPY --from=micromamba /usr/local/bin/_activate_current_env.sh /usr/local/bin/_activate_current_env.sh
COPY --from=micromamba /usr/local/bin/_dockerfile_shell.sh /usr/local/bin/_dockerfile_shell.sh
COPY --from=micromamba /usr/local/bin/_entrypoint.sh /usr/local/bin/_entrypoint.sh
COPY --from=micromamba /usr/local/bin/_activate_current_env.sh /usr/local/bin/_activate_current_env.sh
COPY --from=micromamba /usr/local/bin/_dockerfile_initialize_user_accounts.sh /usr/local/bin/_dockerfile_initialize_user_accounts.sh
COPY --from=micromamba /usr/local/bin/_dockerfile_setup_root_prefix.sh /usr/local/bin/_dockerfile_setup_root_prefix.sh

RUN /usr/local/bin/_dockerfile_initialize_user_accounts.sh && \
    /usr/local/bin/_dockerfile_setup_root_prefix.sh

# Setup the environment
USER root
COPY environment.yml /tmp/environment.yml

# Instruct R processes to use these empty files instead of
# clashing with a local one
RUN touch .Rprofile .Renviron

# Create the environment
RUN micromamba install -y -n base -f /tmp/environment.yml && \
    micromamba clean --all --yes

# Setup the EncyclopeDIA executable:
RUN ln -s /code/encyclopedia-$VERSION-executable.jar /code/encyclopedia.jar

# Set the path. NextFlow seems to circumvent the conda environment
# We also need to set options for the JRE here.
ENV PATH="$MAMBA_ROOT_PREFIX/bin:$PATH" _JAVA_OPTIONS="-Djava.awt.headless=true" VERSION=$VERSION

# Create the entrypoint:
SHELL ["/usr/local/bin/_dockerfile_shell.sh"]
ENTRYPOINT ["/usr/local/bin/_entrypoint.sh"]
CMD []
