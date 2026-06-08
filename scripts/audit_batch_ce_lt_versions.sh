#!/bin/bash
# Ensure all AWS Batch nextflow Compute Environments use the LATEST
# Launch Template version. Audit by default; pass --apply to auto-update
# any CE that lags. Pass --quiet to suppress output when there's nothing
# to do (suitable for cron / startup hooks).
#
# Background: LT v9 had a broken aws-cli install that surfaces only when
# running pipelines whose task containers lack a built-in aws-cli (e.g.
# nf-core minimal biocontainers). v14+ has the fix. Multiple CEs have
# been left behind on older LT versions for 7+ weeks at a time because
# updating the LT does NOT propagate to CEs — each CE pins a version.
# See docs/20260607_BATCH_AMI_AWSCLI_NOT_SELF_CONTAINED.md.

set -e
REGION="${AWS_REGION:-us-west-2}"
MODE="audit"
QUIET=0
for arg in "$@"; do
    case "$arg" in
        --apply) MODE="apply" ;;
        --quiet) QUIET=1 ;;
    esac
done

LAGGING=0
APPLIED=0

CES=$(aws batch describe-compute-environments --region "$REGION" \
  --query "computeEnvironments[?contains(computeEnvironmentName, 'nextflow')].[computeEnvironmentName,computeResources.launchTemplate.launchTemplateId,computeResources.launchTemplate.version]" \
  --output text)

[ $QUIET -eq 0 ] && echo "=== Nextflow CE Launch-Template versions ==="

while read CE_NAME LT_ID LT_VER; do
    [ -z "$LT_ID" ] || [ "$LT_ID" = "None" ] && continue
    LATEST=$(aws ec2 describe-launch-templates --launch-template-ids "$LT_ID" --region "$REGION" \
        --query 'LaunchTemplates[0].LatestVersionNumber' --output text)
    if [ "$LT_VER" = "$LATEST" ]; then
        [ $QUIET -eq 0 ] && printf "  %-30s v%s ✅\n" "$CE_NAME" "$LT_VER"
    else
        LAGGING=$((LAGGING + 1))
        printf "  %-30s v%s → v%s ❌\n" "$CE_NAME" "$LT_VER" "$LATEST"
        if [ "$MODE" = "apply" ]; then
            aws batch update-compute-environment \
                --compute-environment "$CE_NAME" \
                --compute-resources "launchTemplate={launchTemplateId=$LT_ID,version=$LATEST}" \
                --region "$REGION" --output text --query 'computeEnvironmentName' > /dev/null
            APPLIED=$((APPLIED + 1))
            echo "    → upgraded $CE_NAME to LT v$LATEST"
        fi
    fi
done <<< "$CES"

if [ "$MODE" = "apply" ] && [ $APPLIED -gt 0 ]; then
    echo
    echo "Updated $APPLIED CE(s). New worker instances will pick up the new LT;"
    echo "existing idle workers will be replaced as Batch scales."
elif [ $LAGGING -gt 0 ] && [ "$MODE" != "apply" ]; then
    echo
    echo "$LAGGING CE(s) are behind. Re-run with --apply to auto-update."
    exit 1
fi
exit 0
