resource "null_resource" "dependency" {
  triggers = {
    all_dependencies = join(",", var.dependson)
  }
}

resource "null_resource" "install_cli" {
  depends_on = [
    null_resource.dependency
  ]
  connection {
    host        = var.helper_public_ip
    user        = var.helper["username"]
    password    = var.helper["password"]
    private_key = var.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "export KUBECONFIG=~/installer/auth/kubeconfig",
      "curl -kLo cloudctl https://${var.mcm_hub_url}:443/api/cli/cloudctl-linux-amd64",
      "curl -kLo cloudctl-mc-plugin https://${var.mcm_hub_url}:443/rcm/plugins/mc-linux-amd64",
      "chmod +x cloudctl",
      "sudo mv cloudctl /usr/local/bin",
      "cloudctl plugin install -f cloudctl-mc-plugin",
    ] 
  }
}

data "template_file" "import_cluster_config" {
  template = <<EOF
# Licensed Materials - Property of IBM
# IBM Cloud private
# @ Copyright IBM Corp. 2019 All Rights Reserved
# US Government Users Restricted Rights - Use, duplication or disclosure restricted by GSA ADP Schedule Contract with IBM Corp.

## Cluster Configurations
clusterName: "${var.cluster_id}"
clusterNamespace: "${var.cluster_id}"

clusterLabels:
  cloud: "auto-detect"
  vendor: "auto-detect"
  # environment: "Dev"
  # region: "US"

# Configure application management feature
applicationManager:
  enabled: true

# Configure integration to Tiller
tillerIntegration:
  enabled: true

# Configure monitoring for metric collection
prometheusIntegration:
  enabled: true

# Configure gathering of cluster topology data
topologyCollector:
  enabled: true
  updateInterval: 15

# Configure indexing for multicluster search feature
searchCollector:
  enabled: true

# Configure multicluster GRC policy feature
policyController:
  enabled: true

# Configure multicluster service registry feature
serviceRegistry:
  enabled: true
  dnsSuffix: "mcm.svc"
  plugins: "kube-service"

# Configure multicluster metering feature
metering:
  enabled: true

## Image Registry Configurations
%{if var.private_registry_enabled}private_registry_enabled: ${var.private_registry_enabled}
docker_username: ${var.docker_username}
docker_password: ${var.docker_password}
imageRegistry: ${var.imageRegistry}
# imageNamePostfix: 
%{endif}
EOF
}

locals {
  import_cluster = var.mcm_hub_url != "null" && var.mcm_username != "null" && var.mcm_password != "null"
}

resource "null_resource" "import_cluster" {
  count = local.import_cluster ? 1 : 0
  depends_on = [
    null_resource.install_cli
  ]

  connection {
    host        = var.helper_public_ip
    user        = var.helper["username"]
    password    = var.helper["password"]
    private_key = var.ssh_private_key
  }

  provisioner "file" {
    content     = data.template_file.import_cluster_config.rendered
    destination = "/tmp/cluster-import-config.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "export KUBECONFIG=~/installer/auth/kubeconfig",
      "cloudctl login -a ${var.mcm_hub_url} -u ${var.mcm_username} -p ${var.mcm_password} --skip-ssl-validation -n kube-system",
      "cloudctl mc cluster create -f /tmp/cluster-import-config.yaml",
      "cloudctl mc cluster import ${var.cluster_id} -n ${var.cluster_id} > ./cluster-import.yaml",
      "oc create -f ./cluster-import.yaml",
      "oc get pods -n multicluster-endpoint",
    ]
  }
}

