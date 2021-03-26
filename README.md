# OKD Deployment Scripts

This repository contains my OKD deployment scripts. It is designed to deploy an OKD cluster with three control plane nodes and nine workers across three identical hypervisors. A Ceph cluster will be deployed as part of installation, orchestrated and managed by Rook. The Ceph web dashboard will be deployed and available as part of the Ceph deployment. In addition, MetalLB will be deployed into the cluster to provide `LoadBalancer` type services. The internal container registry will be configured to use storage from the Ceph cluster.

This configuration is what I have deployed as my homelab and, with the aid of these scripts, can be cleanly torn down and re-deployed with minimum hassle. In addition, the cluster has full high availability and can be upgraded in-place, which means that clusters can be arbitrarily long-lived.

I'll try to come back and update this repo whenever I re-deploy a cluster, though at this point OKD setup is super stable so there shouldn't be much flux in this repository.

## Prerequisites

### OKD Deployment Procedures

This documentation assumes that you are familiar with the OKD deployment process. Specifically, these scripts deploy OKD onto bare metal user-provisioned infrastructure. This is more commonly known as a baremetal UPI deployment in OKD parlance, and "VMs we make ourselves" by the rest of humanity.

If you are not familiar with OKD baremetal UPI deployments, please read and understand the documentation linked below.
* [OKD Installation overview](https://docs.okd.io/latest/installing/index.html)
* [Installing a cluster on bare metal](https://docs.okd.io/latest/installing/installing_bare_metal/installing-bare-metal.html)

### Terraform

This repo makes heavy use of Terraform to provision the VMs that comprise the cluster. The defaults provided here are almost certainly not going to be applicable to your individual environment, and so you will have to edit some Terraform HCL in order to successfully deploy a cluster. Therefore, familiarity with Terraform and what it does, and HCL as a configuration language, is assumed. If you haven't used Terraform very much before, here are some links to relevant documentation.

* [Terraform](https://www.terraform.io/intro/index.html)
* [Terraform configuration](https://www.terraform.io/docs/language/index.html)
* [Terraform providers](https://www.terraform.io/docs/language/providers/index.html)
* [Terraform modules](https://www.terraform.io/docs/language/modules/index.html)

#### Libvirt Terraform Provider

This repo makes use of the [Libvirt provider for Terraform](https://github.com/dmacvicar/terraform-provider-libvirt) to orchestrate the deployment. This provider must be installed manually. Please follow the installation instructions provided by the README in the linked repository to install the provider prior to deployment.

### Network Environment

OKD requires the administrator to set up some moderately sophisticated networking configuration for successful operation. Specifically, it requires DHCP reservations and various types of DNS records (SRV, PTR, TXT, and A records) to be set up prior to cluster deployment. Anything more capable than your ISP's router should provide the ability to configure DHCP reservations and DNS records, but if you don't have the ability to create these, you will have to figure this out prior to deployment.

The exact networking configuration required is documented as [part of the bare metal installation documentation](https://docs.okd.io/latest/installing/installing_bare_metal/installing-bare-metal.html#installation-network-user-infra_installing-bare-metal). More specific requirements for this setup in particular will be covered later in this guide.

### Load Balancer

OKD requires an external load balancer to handle ingress and API load balancing amongst nodes. While the documentation specifies two separate load balancers, you can combine both into one configuration and deploy a single load balancer to handle both workloads. Load balancer deployment is out of scope for this repo, as there are many ways to tackle this bit of infrastructure. Personally, I've had excellent success with HAProxy.

It is worh repeating: THIS REPOSITORY DOES NOT SET UP AN EXTERNAL LOAD BALANCER. IT MUST BE PRESENT AND CONFIGURED PRIOR TO DEPLOYMENT.

## Hardware Requirements

This repo is designed to deploy onto three identical hypervisors that are set up just so. These are the requirements:

* **At least** 12 cores of CPU (I use Ryzen 5 3600s)
* **At least** 64 GiB of RAM (the more the merrier, really)
* Libvirt and QEMU installed
* A Libvirt LVM storage pool with **at least** 500 GiB of SSD-backed storage named `ssd_pool`
* **At least** 3 block devices 4 TiB or larger. These will be used as storage for container workloads by the cluster.

You will also need to ensure that you can log into the hypervisors from the machine you intend to run the deployment from with passwordless SSH.

## Pre-Deployment One-Time Setup

Once the networking, load balancer, and hardware are all set up, there is some final one-time configuration setup that must be done prior to deployment. Once you have performed this one-time configuration, you can commit it to source control or otherwise save it, as it will not need updating unless you change your underlying infrastructure.

### Configuration files

1. Copy `install-config.yaml.example` to `install-config.yaml`
    1. Update `baseDomain` to be your cluster's intended subdomain.
    1. update `sshKey` to be an SSH public key. The cluster will add this public key to each node's `authorized_hosts`, and is the only way to log into the nodes for debugging purposes.
    1. You should take a look at the rest of the configuration and update it to match your environment if necessary. Documentation on `install-config.yaml` is available [here](https://docs.okd.io/latest/installing/installing_bare_metal/installing-bare-metal.html#installation-bare-metal-config-yaml_installing-bare-metal).
1. Copy `storage/rook-dashboard.yaml.example` to `storage/rook-dashboard.yaml`.
    1. Update `spec.host` with your cluster's subdomain where indicated.
1. Update the `host` default value in `terraform/bootstrap/variables.tf` to point to one of your hypervisors. It does not matter which one.
1. Update the `host` default value in `terraform/hv1/variables.tf` to point to your first hypervisor.
1. Update the `host` default value in `terraform/hv2/variables.tf` to point to your second hypervisor.
1. Update the `host` default value in `terraform/hv3/variables.tf` to point to your third hypervisor.
1. Update the `data_disks` default array in `terraform/hv1/variables.tf` to contain the three block devices you wish to use for cluster storage on your first hypervisor.
1. Update the `data_disks` default array in `terraform/hv2/variables.tf` to contain the three block devices you wish to use for cluster storage on your second hypervisor.
1. Update the `data_disks` default array in `terraform/hv3/variables.tf` to contain the three block devices you wish to use for cluster storage on your third hypervisor.
1. Edit `deploy.sh` and update the `CLUSTER_SUBDOMAIN`, `HYPERVISOR_1`, `HYPERVISOR_2`, and `HYPERVISOR_3` variables to be the cluster subdomain and hostnames of your three hypervisors, respectively.

### DHCP Reservations, DNS Records, and Hypervisor Placements

The Terraform root modules for each hypervisor, as well as the module for the bootstrap, come with hard-coded MAC addresses for each VM it will host. These MAC addresses must have corresponding DHCP reservations, A records, and PTR records, otherwise the cluster will fail to deploy. You may use the MAC addresses provided or change them to fit your environment. The only hard requirement is that they must match.

The deployment expects the following hostnames and hypervisor placements. Note that all DNS records should include the FQDN of the cluster's subdomain. As an example, if the configured cluster subdomain is `cluster.okd.example.com`, then the bootstrap VM's full hostname for the PTR and A records should be `bootstrap.cluster.okd.example.com`.

Bootstrap: `bootstrap`

Masters:
* `master0` on first hypervisor
* `master1` on second hypervisor
* `master2` on third hypervisor

Workers:
* `worker0`, `worker1`, and `worker2` on first hypervisor
* `worker3`, `worker4`, and `worker5` on second hypervisor
* `worker6`, `worker7`, and `worker8` on third hypervisor

## Deployment

Once you have all of the above set up, it is finally time to deploy the cluster. To deploy the latest stable OKD release with the latest stable Rook and Fedora CoreOS, simply run:

```sh
./deploy.sh
```

If you wish to specify an OKD release, that is done via the `OPENSHIFT_INSTALL_RELEASE` environment variable:

```sh
OPENSHIFT_INSTALL_RELEASE="4.7.0-0.okd-2021-03-21-094146" ./deploy.sh
```

If you wish to specify a Rook release, that is done via the `ROOK_TAG` environment variable:

```sh
ROOK_TAG="v1.5.9" ./deploy.sh
```

IF you wish to specify a specific Fedora CoreOS version to deploy as the initial pivot, that is done via the `COREOS_VERSION` environment variable:

```sh
COREOS_VERSION="33.20210301.3.1" ./deploy.sh
```

Of course, any combination of these three environment variables may be set and the script will respect them. Any of the three that are unset will default to the latest stable release of that component.

## Undeployment

To completely tear down the cluster, run the following from the same directory you initially ran `./deploy.sh` from:

```sh
./undeploy.sh
```

If you have to undeploy from a different copy of this repository than the one you initially deployed from, you must create the `.coreos_version` stamp file with the CoreOS version used when installing:

```sh
echo "33.20210301.3.1" > .coreos_version
./undeploy.sh
```
