#!/bin/bash
# Rebuild each domain image WITH its software deps baked in, on the box that owns that domain.
# Pushes a new tag :3.20-deps to ECR (sanity-checked) so a bad build can't clobber :3.20.
KEY=/tmp/biomate_ec2_key_sync
REG=399683337364.dkr.ecr.us-west-2.amazonaws.com
inj(){ aws ec2-instance-connect send-ssh-public-key --instance-id "$1" --availability-zone us-west-2a --instance-os-user ubuntu --ssh-public-key "file://${KEY}.pub" --region us-west-2 >/dev/null 2>&1; }
SSH="ssh -n -i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=20"
# box -> instance, ip, domains it builds
declare -A IID IP DOMS
IID[rf_00]=i-01d95ff9945097b5d; IP[rf_00]=52.36.68.217;  DOMS[rf_00]="general"
IID[rf_01]=i-087c0e15d97ec8f80; IP[rf_01]=54.218.87.146; DOMS[rf_01]="transcriptomics"
IID[rf_02]=i-0fda6379f3af317f2; IP[rf_02]=35.90.77.237;  DOMS[rf_02]="genomics imaging single_cell"
IID[rf_03]=i-053919ffbb8cc512a; IP[rf_03]=35.167.220.240; DOMS[rf_03]="epigenomics proteomics variant_calling metabolomics metagenomics"

for s in rf_00 rf_01 rf_02 rf_03; do
  inj ${IID[$s]}
  $SSH ubuntu@${IP[$s]} "aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin $REG >/dev/null 2>&1" 2>/dev/null
  for dom in ${DOMS[$s]}; do
    echo "[$s] building bioc-domain-$dom:3.20-deps ..."
    inj ${IID[$s]}
    scp -i $KEY -o StrictHostKeyChecking=no /tmp/domain_deps/filtered/$dom.txt ubuntu@${IP[$s]}:/tmp/build_deps.txt 2>/dev/null
    inj ${IID[$s]}
    # build context on the box
    $SSH ubuntu@${IP[$s]} "set -e; rm -rf ~/imgbuild && mkdir ~/imgbuild && cp /tmp/build_deps.txt ~/imgbuild/deps.txt
      sed 's/__DOMAIN__/$dom/' > ~/imgbuild/Dockerfile <<'DF'
$(sed "s/__DOMAIN__/$dom/" /tmp/domain_deps/Dockerfile.tmpl)
DF
      cd ~/imgbuild && docker build -t $REG/biomate/bioc-domain-$dom:3.20-deps . 2>&1 | tail -3
      # sanity: image loads R + a sample dep
      docker run --rm $REG/biomate/bioc-domain-$dom:3.20-deps Rscript -e 'cat(\"R OK\", as.character(getRversion()), nrow(installed.packages()), \"pkgs\\n\")' 2>&1 | tail -1
      docker push $REG/biomate/bioc-domain-$dom:3.20-deps 2>&1 | tail -1" 2>/dev/null
    echo "[$s] $dom done"
  done
done
echo BUILD_DOMAIN_IMAGES_DONE
