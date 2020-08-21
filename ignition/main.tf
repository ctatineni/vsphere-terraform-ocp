resource "null_resource" "dependency" {
  triggers = {
    all_dependencies = join(",", var.dependson)
  }
}

data "template_file" "install_config" {
  template = <<EOF
apiVersion: v1
baseDomain: ${var.base_domain}
compute:
- hyperthreading: Enabled
  name: worker
  replicas: ${var.worker["count"] + var.storage["count"]}
controlPlane:
  hyperthreading: Enabled
  name: master
  replicas: ${var.master["count"]}
metadata:
  name: ${var.cluster_id}
networking:
  clusterNetworks:
  - cidr: ${var.cluster_cidr}
    hostPrefix: ${var.cluster_hostprefix}
  networkType: OpenShiftSDN
  serviceNetwork:
  - ${var.cluster_servicecidr}
platform:
  vsphere:
    vCenter: ${var.vsphere_server}
    username: ${var.vsphere_username}
    password: ${var.vsphere_password}
    datacenter: ${var.vsphere_datacenter}
    defaultDatastore: ${var.vsphere_datastore}
pullSecret: 'PULL_SECRET'
sshKey: '${var.ssh_public_key}'
%{if var.airgapped}additionalTrustBundle: |
  CERTDATA
imageContentSources:
- mirrors:
  - HOSTNAME:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - HOSTNAME:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
%{endif}
EOF
}


resource "null_resource" "generate_ignition" {
  depends_on = [
    null_resource.dependency
  ]

  connection {
    host        = var.helper_public_ip
    user        = var.helper["username"]
    password    = var.helper["password"]
    private_key = var.ssh_private_key
  }

  provisioner "file" {
    content     = data.template_file.install_config.rendered
    destination = "/tmp/install-config.yaml"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir installer/",
      "PULL_SECRET=$(cat /home/sysadmin/ocp_pullsecret.json)",
      "if [[ \"${var.airgapped}\" == \"true\" ]]; then PULL_SECRET=$(cat /home/sysadmin/merged_pullsecret.json); fi",
      "sed -i \"s/PULL_SECRET/$PULL_SECRET/g\" /tmp/install-config.yaml",
      "if [[ \"${var.airgapped}\" == \"true\" ]]; then HOSTNAME=$(hostname -f); fi",
      "if [[ \"${var.airgapped}\" == \"true\" ]]; then sed -i \"s/HOSTNAME/$HOSTNAME/g\" /tmp/install-config.yaml; fi",
      "if [[ \"${var.airgapped}\" == \"true\" ]]; then cp /opt/registry/certs/domain.crt ./ ; fi",
      "if [[ \"${var.airgapped}\" == \"true\" ]]; then sed -i -e 's/^/   /g' ./domain.crt; fi",
      "if [[ \"${var.airgapped}\" == \"true\" ]]; then awk '/CERTDATA/{system(\"cat ./domain.crt\");next}1' /tmp/install-config.yaml > ./install-config.yaml; fi",
      "if [[ \"${var.airgapped}\" == \"true\" ]]; then cp ./install-config.yaml installer/; else cp /tmp/install-config.yaml installer/ ; fi",
      "/usr/local/bin/openshift-install --dir=installer create ignition-configs",
      "sudo cp installer/*.ign /var/www/html/ignition/",
      "sudo chmod -R 644 /var/www/html/ignition/*.ign",
    ]
  }
}
