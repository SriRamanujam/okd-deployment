#!/usr/bin/env bash

# Completely clean up the deployment.

set -euo pipefail

# DEBUG
#set -x

TERRAFORM_HOSTS_DIR="$PWD/terraform"
CONFIG_DIR="$PWD/config"
COREOS_VERSION="$(cat .coreos_version)"

pushd $TERRAFORM_HOSTS_DIR
for d in hv3 hv2 hv1; do
    pushd $d
    terraform destroy --var coreos_version=$COREOS_VERSION --auto-approve
    popd
done

# if it's there, shut down the bootstrap vm separately
pushd bootstrap
terraform destroy --var coreos_version=$COREOS_VERSION --auto-approve
popd

popd

rm -rf $CONFIG_DIR

rm -f ./openshift-install*
rm .coreos_version
