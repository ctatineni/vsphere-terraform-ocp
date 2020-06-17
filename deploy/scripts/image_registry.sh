export KUBECONFIG=${HOME}/installer/auth/kubeconfig
git clone --single-branch --branch release-1.2 https://github.com/rook/rook.git
cp /tmp/cluster-c.yaml rook/cluster/examples/kubernetes/ceph/
cd rook/cluster/examples/kubernetes/ceph/
oc create -f common.yaml
oc create -f operator-openshift.yaml
oc project rook-ceph
sleep 2m
oc create -f cluster-c.yaml
sleep 3m
oc create -f filesystem.yaml
sleep 1m
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
