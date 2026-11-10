#!/usr/bin/env bash
# Keep this process running while the Mac uses Spark's isolated model endpoint.
set -euo pipefail
spark_access_package="${SPARK_ACCESS_PACKAGE:-$HOME/Downloads/spark-ssh-access-package}"
exec ssh -N \
  -o BatchMode=yes -o IdentitiesOnly=yes -o ForwardAgent=no \
  -o StrictHostKeyChecking=yes -o HostKeyAlias=192.168.1.241 \
  -o "UserKnownHostsFile=$spark_access_package/ssh/known_hosts" \
  -i "$spark_access_package/keys/spark_train_ed25519" \
  -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=4 \
  -L 127.0.0.1:18001:127.0.0.1:11435 yzhang@spark-d816.local
