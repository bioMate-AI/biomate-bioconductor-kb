# vLLM serving image for BioMate regulatory LLM.
#
# Wraps the official vllm/vllm-openai image with:
#   - the spot-interruption monitor that drains from ALB before SIGTERM
#   - the BioMate launch script that pins --lora-modules from the manifest
#   - awscli for adapter sync from EFS + ALB deregistration
#
# Built once and pushed to ECR; ASG launch template references it. Bumping
# the vLLM version means rebuild + start-instance-refresh. No customer
# downtime if the ASG min_size keeps at least one healthy node throughout.

ARG VLLM_BASE_TAG=v0.6.4
FROM vllm/vllm-openai:${VLLM_BASE_TAG}

# AWS CLI v2 for spot-monitor: deregister from target group on interruption
# notice + read SSM parameters (adapter manifest, secrets) at launch.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl jq ca-certificates && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    cd /tmp && unzip -q awscliv2.zip && ./aws/install && \
    rm -rf /tmp/aws /tmp/awscliv2.zip && \
    apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

COPY start-vllm.sh /opt/biomate/start-vllm.sh
COPY spot-monitor.sh /opt/biomate/spot-monitor.sh
RUN chmod +x /opt/biomate/start-vllm.sh /opt/biomate/spot-monitor.sh

# Default entrypoint launches vLLM + the spot monitor in parallel. The
# monitor handles graceful drain on Spot Instance termination notice; if
# vLLM exits the container exits (so the ASG replaces it).
ENTRYPOINT ["/opt/biomate/start-vllm.sh"]
