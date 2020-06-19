resource "null_resource" "dependency" {
  triggers = {
    all_dependencies = join(",", var.dependson)
  }
}

resource "null_resource" "waitfor" {
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
      "/usr/local/bin/openshift-install --dir=installer wait-for bootstrap-complete",
    ]
  }
}

resource "null_resource" "waitfor_cluster" {
  depends_on = [
    null_resource.waitfor
  ]
  connection {
    host        = var.helper_public_ip
    user        = var.helper["username"]
    password    = var.helper["password"]
    private_key = var.ssh_private_key
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 2m",
      "export KUBECONFIG=~/installer/auth/kubeconfig",
      "oc get csr -o name | xargs oc adm certificate approve",
      "sleep 2m",
      "oc get csr -o name | xargs oc adm certificate approve",
      "/usr/local/bin/openshift-install --dir=installer wait-for install-complete",
    ]
  }
}

data "template_file" "cluster_config" {
  template = <<EOF
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: ceph/ceph:v14.2.6
    allowUnsupported: false
  dataDirHostPath: /var/lib/rook
  skipUpgradeChecks: false
  continueUpgradeAfterChecksEvenIfNotHealthy: false
  mon:
    count: ${var.storage["count"]}
    allowMultiplePerNode: false
  dashboard:
    enabled: true
    ssl: true
  monitoring:
    enabled: true
    rulesNamespace: rook-ceph
  network:
    hostNetwork: false
  rbdMirroring:
    workers: 0
  crashCollector:
    disable: false
  placement:
    all:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: role
              operator: In
              values:
              - storage-node
      podAffinity:
      podAntiAffinity:
      tolerations:
      - key: storage-node
        operator: Exists
  annotations:
  resources:
    mgr:
      limits:
        cpu: "500m"
        memory: "1024Mi"
      requests:
        cpu: "500m"
        memory: "1024Mi"
  removeOSDsIfOutAndSafeToRemove: false
  storage: # cluster level storage configuration and selection
    useAllNodes: false
    useAllDevices: false
    config:
    nodes:
    %{ for value in  var.storage_hostnames }
    - name: "${value}.${var.cluster_id}.${var.base_domain}"
      devices: # specific devices to use for storage can be specified for each node
      - name: "sdb"
        config:
          osdsPerDevice: "1"
          storeType: bluestore
    %{ endfor }
  disruptionManagement:
    managePodBudgets: false
    osdMaintenanceTimeout: 30
    manageMachineDisruptionBudgets: false
    machineDisruptionBudgetNamespace: openshift-machine-api
EOF
}

resource "null_resource" "install_rook_ceph" {
  count = var.storage["count"]
  depends_on = [
    null_resource.waitfor_cluster
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
      "oc label node ${var.storage_hostnames[count.index]}.${var.cluster_id}.${var.base_domain} role=storage-node",
    ]
  }
}

resource "null_resource" "configure" {

  depends_on = [
    null_resource.install_rook_ceph
  ]

  connection {
    host        = var.helper_public_ip
    user        = var.helper["username"]
    password    = var.helper["password"]
    private_key = var.ssh_private_key
  }
  
  provisioner "file" {
    content     = data.template_file.cluster_config.rendered
    destination = "/tmp/cluster-c.yaml"
  }

  provisioner "file" {
    source      = "${path.module}/scripts"
    destination = "/tmp/deployment_scripts"
  }

  provisioner "remote-exec" {
    inline = [
      "export KUBECONFIG=~/installer/auth/kubeconfig",
      "sudo chmod u+x /tmp/deployment_scripts/*.sh",
      "/tmp/deployment_scripts/image_registry.sh",
      "oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{\"spec\":{\"storage\":{\"pvc\":{}}}}'",
      "oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{\"spec\": {\"defaultRoute\":true}}'",
      "oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{\"spec\": {\"managementState\":\"Managed\"}}'",
    ]
  }

#   provisioner "remote-exec" {
#     inline = [
#       "/usr/local/bin/openshift-install --dir=installer wait-for install-complete",
#     ]
#   }
}
