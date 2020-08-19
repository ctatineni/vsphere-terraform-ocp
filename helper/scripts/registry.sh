#!/bin/bash
wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 -O jq; chmod +x jq; sudo mv jq /usr/local/bin
mkdir -p /opt/registry/{auth,certs,data}
cd /opt/registry/certs
# sudo echo $registry_certificate > /opt/registry/certs/domain.crt
# sudo echo $registry_key > /opt/registry/certs/domain.key
openssl req -newkey rsa:4096 -nodes -sha256 -keyout domain.key -x509 -days 365 -out domain.crt -subj "/C=US/ST=TX/L=Plano/O=IBM/OU=CPAT/CN=helper.ctocp44.ocp.csplab.local/emailAddress=test@test.com"
htpasswd -bBc /opt/registry/auth/htpasswd openshift password
sudo podman run --name mirror-registry -p 5000:5000 -v /opt/registry/data:/var/lib/registry:z -v /opt/registry/auth:/auth:z -e "REGISTRY_AUTH=htpasswd" -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -v /opt/registry/certs:/certs:z -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key -e REGISTRY_COMPATIBILITY_SCHEMA1_ENABLED=true -d docker.io/library/registry:2
sudo cp /opt/registry/certs/domain.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
curl -u openshift:password -k https://helper.ctocp44.ocp.csplab.local:5000/v2/_catalog 
sudo podman login -u openshift -p password --authfile $HOME/pullsecret_config.json helper.ctocp44.ocp.csplab.local:5000
jq -c --argjson var "$(jq .auths $HOME/pullsecret_config.json)" '.auths += $var' $HOME/ocp_pullsecret.json > $HOME/merged_pullsecret.json

export OCP_RELEASE=4.4.18-x86_64
export LOCAL_REGISTRY='helper.ctocp44.ocp.csplab.local:5000' 
export LOCAL_REPOSITORY='ocp4/openshift4' 
export PRODUCT_REPO='openshift-release-dev' 
export LOCAL_SECRET_JSON='/home/sysadmin/merged_pullsecret.json'
export RELEASE_NAME="ocp-release"

oc adm -a ${LOCAL_SECRET_JSON} release mirror \
     --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE} \
     --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
     --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}

oc adm -a ${LOCAL_SECRET_JSON} release extract --command=openshift-install "${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}"

sudo mv -f openshift-install /usr/local/bin/
