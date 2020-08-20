provider "vsphere" {
  version              = "< 1.16.0"
  user                 = var.vsphere_username
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = var.vsphere_allow_insecure
}

data "vsphere_datacenter" "datacenter" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "node" {
  name          = var.vsphere_node_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "images" {
  name          = var.vsphere_image_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "public" {
  name          = var.vsphere_public_network
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "private" {
  name          = var.vsphere_private_network
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

locals {
  all_hostnames = concat(list(var.bootstrap_hostname), var.master_hostnames, var.worker_hostnames, var.storage_hostnames)
  all_ips       = concat(list(var.bootstrap_ip), var.master_ips, var.worker_ips, var.storage_ips)
  all_count     = 1 + var.master["count"] + var.worker["count"] + var.storage["count"]
  all_type = concat(
    data.template_file.bootstrap_type.*.rendered,
    data.template_file.master_type.*.rendered,
    data.template_file.worker_type.*.rendered,
    data.template_file.storage_type.*.rendered,
  )
  all_index = concat(
    data.template_file.bootstrap_index.*.rendered,
    data.template_file.master_index.*.rendered,
    data.template_file.worker_index.*.rendered,
    data.template_file.storage_index.*.rendered,
  )

  all_hostnames_no_bootstrap = concat(var.master_hostnames, var.worker_hostnames, var.storage_hostnames)
  all_ips_no_bootstrap       = concat(var.master_ips, var.worker_ips, var.storage_ips)
  all_count_no_bootstrap     = var.master["count"] + var.worker["count"] + var.storage["count"]
  all_type_no_bootstrap = concat(
    data.template_file.master_type.*.rendered,
    data.template_file.worker_type.*.rendered,
    data.template_file.storage_type.*.rendered,
  )
  all_index_no_bootstrap = concat(
    data.template_file.master_index.*.rendered,
    data.template_file.worker_index.*.rendered,
    data.template_file.storage_index.*.rendered,
  )
}

data "template_file" "bootstrap_type" {
  count    = 1
  template = "bootstrap"
}

data "template_file" "master_type" {
  count    = var.master["count"]
  template = "master"
}

data "template_file" "worker_type" {
  count    = var.worker["count"]
  template = "worker"
}

data "template_file" "storage_type" {
  count    = var.storage["count"]
  template = "worker"
}

data "template_file" "bootstrap_index" {
  count    = 1
  template = count.index + 1
}

data "template_file" "master_index" {
  count    = var.master["count"]
  template = count.index + 1
}

data "template_file" "worker_index" {
  count    = var.worker["count"]
  template = count.index + 1
}

data "template_file" "storage_index" {
  count    = var.storage["count"]
  template = count.index + 1 + var.worker["count"]
}


# SSH Key for VMs
resource "tls_private_key" "installkey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# resource "local_file" "write_private_key" {
#   content         = tls_private_key.installkey.private_key_pem
#   filename        = "${path.root}/artifacts/openshift_rsa"
#   file_permission = 0600
# }

# resource "local_file" "write_public_key" {
#   content         = tls_private_key.installkey.public_key_openssh
#   filename        = "${path.root}/artifacts/openshift_rsa.pub"
#   file_permission = 0600
# }

module "helper" {
  source             = "./helper"
  datacenter_id      = data.vsphere_datacenter.datacenter.id
  datastore_id       = data.vsphere_datastore.node.id
  resource_pool_id   = vsphere_resource_pool.pool.id
  folder_id          = vsphere_folder.folder.path
  vminfo             = var.helper
  public_ip          = var.helper_public_ip
  private_ip         = var.helper_private_ip
  public_network_id  = data.vsphere_network.public.id
  private_network_id = data.vsphere_network.private.id
  public_gateway     = var.public_network_gateway
  private_gateway    = var.private_network_gateway
  public_netmask     = var.public_network_netmask
  private_netmask    = var.private_network_netmask
  cluster_id         = var.openshift_cluster_id
  base_domain        = var.openshift_base_domain
  dns_servers        = var.public_network_nameservers
  ssh_private_key    = tls_private_key.installkey.private_key_pem
  ssh_public_key     = tls_private_key.installkey.public_key_openssh
  bootstrap_hostname = var.bootstrap_hostname
  bootstrap_ip       = var.bootstrap_ip
  master_hostnames   = var.master_hostnames
  master_ips         = var.master_ips
  worker_hostnames   = var.worker_hostnames
  worker_ips         = var.worker_ips
  storage_hostnames  = var.storage_hostnames
  storage_ips        = var.storage_ips
  binaries           = var.binaries
  pull_secret        = var.openshift_pull_secret
  registry_certificate = var.registry_certificate
  registry_key        = var.registry_key
  airgapped          = var.airgapped
}

module "createisos" {
  source = "./createisos"
  dependson = [
    module.helper.module_completed
  ]
  binaries              = var.binaries
  bootstrap             = var.bootstrap
  bootstrap_hostname    = var.bootstrap_hostname
  bootstrap_ip          = var.bootstrap_ip
  master                = var.master
  master_hostnames      = var.master_hostnames
  master_ips            = var.master_ips
  worker                = var.worker
  worker_hostnames      = var.worker_hostnames
  worker_ips            = var.worker_ips
  storage               = var.storage
  storage_hostnames     = var.storage_hostnames
  storage_ips           = var.storage_ips
  helper                = var.helper
  helper_public_ip      = var.helper_public_ip
  helper_private_ip     = var.helper_private_ip
  ssh_private_key       = tls_private_key.installkey.private_key_pem
  network_device        = var.coreos_network_device
  cluster_id            = var.openshift_cluster_id
  base_domain           = var.openshift_base_domain
  private_netmask       = var.private_network_netmask
  private_gateway       = var.private_network_gateway
  openshift_nameservers = var.use_helper_for_node_dns ? [var.helper_private_ip] : var.public_network_nameservers

  vsphere_server               = var.vsphere_server
  vsphere_username             = var.vsphere_username
  vsphere_password             = var.vsphere_password
  vsphere_allow_insecure       = var.vsphere_allow_insecure
  vsphere_image_datastore      = var.vsphere_image_datastore
  vsphere_image_datastore_path = var.vsphere_image_datastore_path
}

module "ignition" {
  source = "./ignition"
  dependson = [
    module.createisos.module_completed
  ]
  helper              = var.helper
  helper_public_ip    = var.helper_public_ip
  ssh_private_key     = tls_private_key.installkey.private_key_pem
  ssh_public_key      = tls_private_key.installkey.public_key_openssh
  binaries            = var.binaries
  base_domain         = var.openshift_base_domain
  master              = var.master
  worker              = var.worker
  storage             = var.storage
  cluster_id          = var.openshift_cluster_id
  cluster_cidr        = var.openshift_cluster_cidr
  cluster_hostprefix  = var.openshift_host_prefix
  cluster_servicecidr = var.openshift_service_cidr
  vsphere_server      = var.vsphere_server
  vsphere_username    = var.vsphere_username
  vsphere_password    = var.vsphere_password
  vsphere_datacenter  = var.vsphere_datacenter
  vsphere_datastore   = var.vsphere_node_datastore
  pull_secret         = var.openshift_pull_secret
  registry_certificate = var.registry_certificate
  airgapped          = var.airgapped
}

module "bootstrap" {
  source = "./bootstrap"
  dependson = [
    module.ignition.module_completed
  ]
  vminfo               = var.bootstrap
  resource_pool_id     = vsphere_resource_pool.pool.id
  datastore_id         = data.vsphere_datastore.node.id
  image_datastore_id   = data.vsphere_datastore.images.id
  image_datastore_path = var.vsphere_image_datastore_path
  folder               = vsphere_folder.folder.path
  cluster_id           = var.openshift_cluster_id
  network_id           = data.vsphere_network.private.id
}

module "master" {
  source = "./nodes"
  dependson = [
    module.bootstrap.module_completed
  ]
  vminfo               = var.master
  vmtype               = "master"
  resource_pool_id     = vsphere_resource_pool.pool.id
  datastore_id         = data.vsphere_datastore.node.id
  image_datastore_id   = data.vsphere_datastore.images.id
  image_datastore_path = var.vsphere_image_datastore_path
  folder               = vsphere_folder.folder.path
  cluster_id           = var.openshift_cluster_id
  network_id           = data.vsphere_network.private.id
}

module "worker" {
  source = "./nodes"
  dependson = [
    module.bootstrap.module_completed
  ]
  vminfo               = var.worker
  vmtype               = "worker"
  resource_pool_id     = vsphere_resource_pool.pool.id
  datastore_id         = data.vsphere_datastore.node.id
  image_datastore_id   = data.vsphere_datastore.images.id
  image_datastore_path = var.vsphere_image_datastore_path
  folder               = vsphere_folder.folder.path
  cluster_id           = var.openshift_cluster_id
  network_id           = data.vsphere_network.private.id
}

module "storage" {
  source       = "./storage"
  count_offset = var.worker["count"]
  dependson = [
    module.bootstrap.module_completed
  ]
  vminfo               = var.storage
  vmtype               = "worker"
  resource_pool_id     = vsphere_resource_pool.pool.id
  datastore_id         = data.vsphere_datastore.node.id
  image_datastore_id   = data.vsphere_datastore.images.id
  image_datastore_path = var.vsphere_image_datastore_path
  folder               = vsphere_folder.folder.path
  cluster_id           = var.openshift_cluster_id
  network_id           = data.vsphere_network.private.id
}

module "deploy" {
  dependson = [
    module.ignition.module_completed,
    module.master.module_completed,
    module.worker.module_completed,
    module.storage.module_completed
  ]
  source            = "./deploy"
  helper            = var.helper
  helper_public_ip  = var.helper_public_ip
  ssh_private_key   = tls_private_key.installkey.private_key_pem
  storage           = var.storage
  storage_hostnames = var.storage_hostnames
  cluster_id        = var.openshift_cluster_id
  base_domain       = var.openshift_base_domain
}

module "post" {
  dependson = [
    module.createisos.module_completed,
    module.ignition.module_completed,
    module.master.module_completed,
    module.worker.module_completed,
    module.storage.module_completed,
    module.deploy.module_completed
  ]
  source               = "./post"
  helper               = var.helper
  helper_public_ip     = var.helper_public_ip
  ssh_private_key      = tls_private_key.installkey.private_key_pem
  master_hostnames     = var.master_hostnames
  worker_hostnames     = var.worker_hostnames
  storage_hostnames    = var.storage_hostnames
  apps_certificate     = var.apps_certificate
  apps_certificate_key = var.apps_certificate_key
  api_certificate      = var.api_certificate
  api_certificate_key  = var.api_certificate_key
  custom_ca_bundle     = var.custom_ca_bundle
  base_domain          = var.openshift_base_domain
  cluster_id           = var.openshift_cluster_id
}

resource "vsphere_folder" "folder" {
  path          = "Sandbox/ctatineni/${var.openshift_cluster_id}"
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

resource "vsphere_resource_pool" "parent" {
  name                    = "ctatineni"
  parent_resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id}
}

resource "vsphere_resource_pool" "pool" {
  name                    = var.openshift_cluster_id
  parent_resource_pool_id = data.vsphere_resource_pool.parent.resource_pool_id}
}
      
      

