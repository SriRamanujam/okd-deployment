#!/bin/bash

# Deploys the cluster. After setting the necessary inline configuration variables
# in the script below, you can run the script like so:
# ```sh
# $ ROOK_TAG="v1.5.9" ./deploy.sh
# ```
# This will deploy a cluster using the latest stable OKD release and the latest version
# of FCOS. It will deploy Rook v1.5.9 into the cluster. You can optionally specify a
# version of FCOS to deploy using the COREOS_VERSION environment variable, and/or a specific
# version of OKD with the OPENSHIFT_INSTALL_RELEASE environment variable.

set -euo pipefail

# DEBUG
#set -x

##### INLINE CONFIGURATION VARIABLES ####
# Set these up to match your enviroment before you run the script.
# Note that the cluster subdomain has to match whatever you set up for
# DNS.

CLUSTER_SUBDOMAIN="cluster.okd.example.com"
HYPERVISOR_1="hv1.okd.example.com"
HYPERVISOR_2="hv2.okd.example.com"
HYPERVISOR_3="hv3.okd.example.com"

##### END INLINE CONFIGURATION VARIABLES ####

# check dependencies
for cmd in 'curl' 'jq' 'mktemp' 'oc' 'tar' 'mkdir' 'cp' 'mv' 'rm' 'sed' 'terraform' 'ssh' 'qemu-img' 'openssl'; do
    if ! $(command -v $cmd &>/dev/null); then
        echo "This script requires the $cmd binary to be present in the system's PATH. Please install it before continuing."
        exit 1
    fi
done

if [[ -z ${OPENSHIFT_INSTALL_RELEASE+x} ]]; then
    # get the latest okd release from the repo
    OPENSHIFT_INSTALL_RELEASE="$(curl -s https://api.github.com/repos/openshift/okd/releases | jq -r '.[0].tag_name')"
    OKD_DOWNLOAD_URL="$(curl -s https://api.github.com/repos/openshift/okd/releases | jq -r '.[0].assets[] | select(.name | contains("openshift-install-linux")) | .browser_download_url')"
fi

echo "Using OKD release $OPENSHIFT_INSTALL_RELEASE to bring up cluster."

if [[ -z ${ROOK_TAG+x} ]]; then
    # get the latest Rook release tag from the repo
    ROOK_TAG="$(curl -s https://api.github.com/repos/rook/rook/releases | jq -r '.[0].tag_name')"
fi

echo "Deploying Rook release $ROOK_TAG into cluster."

if [[ -z ${COREOS_VERSION+x} ]]; then
    COREOS_VERSION=$(curl -s https://builds.coreos.fedoraproject.org/streams/stable.json | jq -r '.architectures.x86_64.artifacts.qemu.release')
fi

echo "Bootstrapping cluster using Fedora CoreOS $COREOS_VERSION."

echo "$COREOS_VERSION" > .coreos_version

PROJECT_DIR="$PWD"
INSTALL_DIR="$PROJECT_DIR/config"
STORAGE_DIR="$PROJECT_DIR/storage"
LB_DIR="$PROJECT_DIR/lb"
KUBECONFIG_PATH="$INSTALL_DIR/auth/kubeconfig"
TERRAFORM_HOSTS_BASE_DIR="$PROJECT_DIR/terraform"

OPENSHIFT_INSTALL="$PROJECT_DIR/openshift-install-${OPENSHIFT_INSTALL_RELEASE}"

get_installer() {
    TEMPDIR=$(mktemp -d)
    pushd $TEMPDIR
    if [[ -z ${OKD_DOWNLOAD_URL+x} ]]; then
        oc adm release extract --command 'openshift-install' "quay.io/openshift/okd:$OPENSHIFT_INSTALL_RELEASE" || \
        oc adm release extract --command 'openshift-install' "registry.svc.ci.openshift.org/origin/release:$OPENSHIFT_INSTALL_RELEASE"
    else
        echo "Downloading OKD release $OPENSHIFT_INSTALL_RELEASE..."
        curl -LO $OKD_DOWNLOAD_URL
        tar -xf "openshift-install-linux-$OPENSHIFT_INSTALL_RELEASE.tar.gz"
    fi
    popd
    mv "$TEMPDIR/openshift-install" ${OPENSHIFT_INSTALL}
    rm -rf $TEMPDIR
}

echo "Creating install configuration manifests..."

[[ -f "$OPENSHIFT_INSTALL" ]] || get_installer
[[ -d "$INSTALL_DIR" ]] && rm -rf "$INSTALL_DIR"

mkdir -p "$INSTALL_DIR"
cp ./install-config.yaml "$INSTALL_DIR"

"${OPENSHIFT_INSTALL}" create manifests --dir="$INSTALL_DIR"

sed -i -e 's/mastersSchedulable: true/mastersSchedulable: false/' "$INSTALL_DIR/manifests/cluster-scheduler-02-config.yml"

"${OPENSHIFT_INSTALL}" create ignition-configs --dir="$INSTALL_DIR"

echo "Done. Now initializing cluster..."

# we do the bootstrap last so that all the actual infra can start bootstrapping ASAP
for directory in hv3 hv2 hv1 bootstrap; do
    pushd "$TERRAFORM_HOSTS_BASE_DIR/$directory"
    [[ -d .terraform ]] || terraform init
    terraform apply --var "coreos_version=$COREOS_VERSION" --auto-approve
    popd
done

echo "Done."

echo "Now we wait for the bootstrap to complete."

"${OPENSHIFT_INSTALL}" --dir=config wait-for bootstrap-complete --log-level=debug

echo "The cluster is provisionally available. Removing the bootstrap VM..."

pushd "$TERRAFORM_HOSTS_BASE_DIR/bootstrap"
terraform destroy --var "coreos_version=$COREOS_VERSION" --auto-approve
popd

echo "Done."

echo -n "Giving the load balancer some time to realize that the bootstrap VM is out of the rotation..."
sleep 20
echo "Done."

echo "We now have to wait for.... something to come up correctly so that the rook yaml can go in properly."
echo "I don't actually know what that something is, but I think it has something to do with the apiserver."
echo "Until I figure that out, just wait for 10 minutes and hope."
sleep 600

export KUBECONFIG="$KUBECONFIG_PATH"

#### AUTOMATICALLY APPROVE WORKER CSRS #########

echo "Approving worker CSRs..."

while [[ $(oc get csr | grep -cF kubelet-serving) -lt 12 ]] || [[ $(oc get --no-headers nodes | grep -cF Ready) -lt 12 ]]; do
    oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs --no-run-if-empty oc adm certificate approve
    sleep 1
done

echo "Done."

###### END AUTOMATICALLY APPROVE WORKER CSRS ########

###### SET UP ROLES AND TAGS FOR EACH CLUSTER NODE BEGIN ######

# Do I need this? Probably not. Am I doing it just in case? Yes.
oc label node master0."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_1}"
oc label node master1."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_2}"
oc label node master2."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_3}"

for index in {0..2}; do
    while true; do
        if oc label node worker$index."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_1}"; then
            break
        else
            sleep 1
        fi
    done
done

for index in {3..5}; do
    while true; do
        if oc label node worker$index."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_2}"; then
            break
        else
            sleep 1
        fi
    done
done

for index in {6..8}; do
    while true; do
        if oc label node worker$index."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_3}"; then
            break
        else
            sleep 1
        fi
    done
done

###### SET UP ROLES AND TAGS FOR EACH CLUSTER NODE END ######

###### CEPH BEGIN ######

echo "We now continue by setting up storage (Ceph + Rook)."
oc apply -f https://raw.githubusercontent.com/rook/rook/${ROOK_TAG}/cluster/examples/kubernetes/ceph/crds.yaml -f https://raw.githubusercontent.com/rook/rook/${ROOK_TAG}/cluster/examples/kubernetes/ceph/common.yaml
sleep 5
oc apply -f https://raw.githubusercontent.com/rook/rook/${ROOK_TAG}/cluster/examples/kubernetes/ceph/operator-openshift.yaml
sleep 5
oc apply -f "$STORAGE_DIR/cluster.yaml"
sleep 5
oc apply -f "$STORAGE_DIR/filesystem_ec.yaml"
sleep 5
oc apply -f "$STORAGE_DIR/blockpool_replicated.yaml"
sleep 5
oc apply -f "$STORAGE_DIR/storageclass-block.yaml"
sleep 5
oc apply -f "$STORAGE_DIR/storageclass-cephfs.yaml"
sleep 1
oc apply -f "$STORAGE_DIR/rook-dashboard.yaml"
sleep 30

echo -n "Waiting for Ceph to come up..."
while true; do
    if [[ $(oc get pods -n rook-ceph 2>/dev/null | grep rook-ceph-osd | grep -v prepare | grep -cF 'Running') -ge 9 ]]; then
        break
    else
        sleep 1
    fi
done
echo "done."

###### CEPH END ######

###### REGISTRY CONFIG BEGIN ######

echo -n "Unsticking the rook-ceph-operator by restarting it..."
oc -n rook-ceph delete pod -l app=rook-ceph-operator
echo "Done."

echo "Patching registry config so that it binds the PVC..."

oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec": {"managementState": "Managed", "storage": {"pvc": {"claim": ""}}}}'

echo -n "Done. Waiting for the PVC to bind..."

# see if the PVC is bound
PVC_BIND_SUCCESS=no
for i in {0..120}; do
    if oc get pvc -n openshift-image-registry | grep -q Bound; then
        PVC_BIND_SUCCESS=yes
        break
    else
        sleep 1
    fi
done

if [[ "$PVC_BIND_SUCCESS" == "no" ]]; then
    echo "Something is wrong, the PVC did not bind successfully. Bailing!"
    exit 1
fi

echo "done."

echo "Patching registry so that it is available externally..."

oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge

echo "done."
###### REGISTRY CONFIG END ######

###### DEPLOY LOADBALANCER BEGIN ######

echo "Configuring load balancer..."
oc apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/namespace.yaml
sed -e s,REPLACE_WITH_MIN_USER_ID,$(oc get project metallb-system -o json | jq -r '.metadata.annotations."openshift.io/sa.scc.uid-range"' | cut -f1 -d'/'),g -e s,REPLACE_WITH_MAX_USER_ID,$(expr $(oc get project metallb-system -o json | jq -r '.metadata.annotations."openshift.io/sa.scc.uid-range"' | sed 's,/, + ,')),g "$LB_DIR/metallb_0.9.5.yaml" | oc apply -f -
oc create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
oc adm policy add-scc-to-user privileged -n metallb-system -z speaker
oc apply -f "$LB_DIR/configuration.yaml"
echo "Done."

##### DEPLOY LOADBALANCER END ######

"${OPENSHIFT_INSTALL}" --dir=config wait-for install-complete --log-level=debug
