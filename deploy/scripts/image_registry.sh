export KUBECONFIG=${HOME}/installer/auth/kubeconfig
cd rook/cluster/examples/kubernetes/ceph/
oc create -f common.yaml
oc create -f operator-openshift.yaml
oc project rook-ceph
sleep 2m
oc create -f cluster-c.yaml
sleep 5m
oc create -f filesystem.yaml
sleep 2m
oc create -f csi/rbd/storageclass.yaml
oc create -f csi/cephfs/storageclass.yaml

cat <<EOF | oc create -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  finalizers:
  - kubernetes.io/pvc-protection
  name: image-registry-storage
  namespace: openshift-image-registry
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  persistentVolumeReclaimPolicy: Retain
  storageClassName: csi-cephfs
EOF
