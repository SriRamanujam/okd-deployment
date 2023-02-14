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
for cmd in 'ansible-playbook' 'kustomize' 'aws' 'curl' 'jq' 'mktemp' 'oc' 'tar' 'mkdir' 'cp' 'mv' 'rm' 'sed' 'terraform' 'ssh' 'openssl'; do
    if ! $(command -v $cmd &>/dev/null); then
        echo "This script requires the $cmd binary to be present in the system's PATH. Please install it before continuing."
        exit 1
    fi
done

if [[ -z ${OPENSHIFT_INSTALL_RELEASE+x} ]]; then
    # get the latest okd release from the repo
    OPENSHIFT_INSTALL_RELEASE="$(curl -s https://api.github.com/repos/okd-project/okd/releases | jq -r '.[0].tag_name')"
    OKD_DOWNLOAD_URL="$(curl -s https://api.github.com/repos/okd-project/okd/releases | jq -r '.[0].assets[] | select(.name | contains("openshift-install-linux")) | .browser_download_url')"
fi

echo "Using OKD release $OPENSHIFT_INSTALL_RELEASE to bring up cluster."

if [[ -z ${COREOS_VERSION+x} ]]; then
    COREOS_VERSION=$(curl -s https://builds.coreos.fedoraproject.org/streams/stable.json | jq -r '.architectures.x86_64.artifacts.qemu.release')
fi

echo "Bootstrapping cluster using Fedora CoreOS $COREOS_VERSION."

echo "$COREOS_VERSION" > .coreos_version

PROJECT_DIR="$PWD"
INSTALL_DIR="$PROJECT_DIR/config"
STORAGE_DIR="$PROJECT_DIR/storage"
LB_DIR="$PROJECT_DIR/lb"
MONITORING_DIR="$PROJECT_DIR/monitoring"
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

ansible-playbook -i "${HYPERVISOR_1},${HYPERVISOR_2},${HYPERVISOR_3}," --user root ansible/main.yml --extra-vars "coreos_version=${COREOS_VERSION}"

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

export KUBECONFIG="$KUBECONFIG_PATH"

echo "Waiting for API server to come up fully..."
until oc wait --for=condition=Degraded=False clusteroperator kube-apiserver; do
    echo "Still waiting..."
done

until oc wait --for=condition=Progressing=False clusteroperator kube-apiserver; do
    echo "Still waiting..."
done

until oc wait --for=condition=Available=True clusteroperator kube-apiserver; do
    echo "Still waiting..."
done

echo "Done."

#### AUTOMATICALLY APPROVE WORKER CSRS #########

echo "Approving worker CSRs..."

while [[ $(oc get csr | grep -cF kubelet-serving) -lt 12 ]] || [[ $(oc get --no-headers nodes | grep -cF Ready) -lt 12 ]]; do
    oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs --no-run-if-empty oc adm certificate approve
    sleep 1
done

echo "Done."

###### END AUTOMATICALLY APPROVE WORKER CSRS ########

###### SET UP ROLES AND TAGS FOR EACH CLUSTER NODE BEGIN ######


# We label each node with two particular sets of labels.
# * topology.rook.io/chassis is to inform rook about the physical topology of the cluster. used as part of the input to the ceph CRUSH map.
# * topology.kubernetes.io/zone is used to denote the AZ, basically, of the cluster. Each hypervisor is basically its own AZ regardless.
#   used by the ingress controller to ensure proper spread of replicas.

oc label node master0."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_1}"
oc label node master1."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_2}"
oc label node master2."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_3}"

oc label node master0."${CLUSTER_SUBDOMAIN}" topology.kubernetes.io/zone="${HYPERVISOR_1}"
oc label node master1."${CLUSTER_SUBDOMAIN}" topology.kubernetes.io/zone="${HYPERVISOR_2}"
oc label node master2."${CLUSTER_SUBDOMAIN}" topology.kubernetes.io/zone="${HYPERVISOR_3}"

for index in {0..2}; do
    until oc label node worker$index."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_1}"; do
        sleep 1
    done

    until oc label node worker$index."${CLUSTER_SUBDOMAIN}" topology.kubernetes.io/zone="${HYPERVISOR_1}"; do
        sleep 1
    done
done

for index in {3..5}; do
    until oc label node worker$index."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_2}"; do
        sleep 1
    done

    until oc label node worker$index."${CLUSTER_SUBDOMAIN}" topology.kubernetes.io/zone="${HYPERVISOR_2}"; do
        sleep 1
    done
done

for index in {6..8}; do
    until oc label node worker$index."${CLUSTER_SUBDOMAIN}" topology.rook.io/chassis="${HYPERVISOR_3}"; do
        sleep 1
    done

    until oc label node worker$index."${CLUSTER_SUBDOMAIN}" topology.kubernetes.io/zone="${HYPERVISOR_3}"; do
        sleep 1
    done
done

###### SET UP ROLES AND TAGS FOR EACH CLUSTER NODE END ######

###### CEPH BEGIN ######

echo "We now continue by setting up storage (Ceph + Rook)."

until kustomize build "$STORAGE_DIR" | oc apply -f - ; do
    sleep 1
done

echo "Waiting for Ceph to come up..."
until oc wait --timeout=1h --for=condition=Ready=True -n rook-ceph cephcluster rook-ceph; do
    echo "Still waiting..."
done
echo "done."

###### CEPH END ######

###### REGISTRY CONFIG BEGIN ######

echo "Creating image registry storage bucket..."
oc -n openshift-image-registry apply -F "$REGISTRY_DIR/bucketclaim.yaml"

until oc -n openshift-image-registry wait --for=jsonpath='{.status.phase}'=Bound obc/openshift-image-registry-bucket; do
    echo "Waiting for bucket creation..."
    sleep 1
done

echo "Creating the image registry secret..."
export $(oc -n openshift-image-registry get secret openshift-image-registry-bucket -o jsonpath='{.data}' | jq -r 'map_values(@base64d) | to_entries | .[] | .key + "=" + .value')
oc create secret generic image-registry-private-configuration-user --from-literal=REGISTRY_STORAGE_S3_ACCESSKEY=$AWS_ACCESS_KEY_ID --from-literal=REGISTRY_STORAGE_S3_SECRETKEY=$AWS_SECRET_ACCESS_KEY --namespace openshift-image-registry


echo "Patching registry config so that it uses the bucket..."
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec": "replicas": "2", {"managementState": "Managed", "storage": {"s3": {"region": "us-east-1", "bucket": "'$(oc -n openshift-image-registry get cm openshift-image-registry-bucket -o jsonpath="{.data.BUCKET_NAME}")'", "regionEndpoint": "https://'$(oc get route -n rook-ceph rook-ceph-rgw-library-objectstore -o jsonpath="{.status.ingress[0].host}")'"}}}}'

echo "Waiting for registry operator to finish setting up the bucket..."
# There's no good way to monitor for this, so we just sleep and hope.
sleep 10

echo "Resetting public block policy so that the registry doesn't lock itself out by mistake..."

aws --endpoint=https://$(oc get ingress -n rook-ceph rook-ceph-rgw-library-objectstore -o json | jq -r '.spec.rules[] | select (.host | startswith("rook-ceph")) | .host') s3api put-public-access-block --bucket $(oc -n openshift-image-registry get cm openshift-image-registry-bucket -o jsonpath='{.data.BUCKET_NAME}') --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY

echo -n "Done."

echo "Patching registry so that it is available externally..."

oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge

echo "done."
###### REGISTRY CONFIG END ######

###### DEPLOY LOADBALANCER BEGIN ######

echo "Configuring load balancer..."
until kustomize build "$LB_DIR" | oc apply -f - ; do
    sleep 1
done
oc adm policy add-scc-to-user privileged -n metallb-system -z speaker
echo "Done."

##### DEPLOY LOADBALANCER END ######

##### CONFIGURE MONITORING #####

echo "Configuring monitoring..."
oc apply -f "$MONITORING_DIR/configmap.yaml"
echo "Done."

##### CONFIGURE MONITORING DONE #####

#### DISBALE SAMPLES OPERATOR BEGIN ######

echo "Disabling samples operator..."
oc patch configs.samples.operator.openshift.io cluster --type merge --patch '{"spec": {"managementState": "Removed"}}'
echo "Done."

#### DISABLE SAMPLES OPERATOR END #####

"${OPENSHIFT_INSTALL}" --dir=config wait-for install-complete --log-level=debug
