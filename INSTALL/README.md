
# OpenShift Container Platform 4.14
# RUNBOOK OPERATIVO ENTERPRISE – NOC READY (FULL COMMANDS)
## VMware vSphere IPI

---

# 1. ARCHITETTURA ENTERPRISE

Client → DNS → F5/HAProxy → API VIP (6443) → Master (3)
Client → DNS → F5/HAProxy → Ingress VIP (80/443) → Router (Infra)

DNS richiesti:
- api.<cluster>.<domain>
- api-int.<cluster>.<domain>
- *.apps.<cluster>.<domain>

---
# 2. PREPARAZIONE BASTION

## Download installer

mkdir -p /opt/ocp
cd /opt/ocp

wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.14.*/openshift-install-linux.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.14.*/openshift-client-linux.tar.gz

tar zxvf openshift-install-linux.tar.gz
chmod +x openshift-install

tar zxvf openshift-client-linux.tar.gz -C /usr/local/bin
chmod +x /usr/local/bin/oc

---

## Creazione chiave SSH

ssh-keygen -t ed25519 -N '' -f ~/.ssh/ocp4key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/ocp4key
cat ~/.ssh/ocp4key.pub

---

## Import certificati vCenter

curl -k -O https://<vcenter>/certs/download.zip
unzip download.zip
cp certs/lin/* /etc/pki/ca-trust/source/anchors/
update-ca-trust extract

Verifica:
openssl s_client -connect vcenter:443

---
# 3. INSTALLAZIONE

./openshift-install create cluster --dir=install_dir --log-level=debug

Post install:
export KUBECONFIG=install_dir/auth/kubeconfig
oc get co
oc get nodes
oc get machines -A

---
# 4. BACKUP ETCD

## Backup manuale

ssh -i ~/.ssh/ocp4key core@<master-ip>
sudo -i
/usr/local/bin/cluster-backup.sh /home/core/backup
ls -lh /home/core/backup

---

## Script backup

#!/bin/bash
DATE=$(date +%F)
ssh -i ~/.ssh/ocp4key core@<master-ip> "sudo /usr/local/bin/cluster-backup.sh /home/core/backup"
rsync -av -e "ssh -i ~/.ssh/ocp4key" core@<master-ip>:/home/core/backup /backup-etcd/$DATE

Crontab:
0 2 * * * /usr/local/sbin/backup-etcd.sh

---
# 5. RIPRISTINO ETCD

ssh core@<master-ip>
sudo -i
systemctl stop kubelet
cluster-restore.sh /home/core/backup/<snapshot>
systemctl start kubelet

---
# 6. CERTIFICATI

## Ingress

oc create secret tls wildcard-cert --cert=wildcard.crt --key=wildcard.key -n openshift-ingress

oc patch ingresscontroller default -n openshift-ingress-operator --type=merge -p '{"spec":{"defaultCertificate":{"name":"wildcard-cert"}}}'

---

## API

oc create secret tls api-cert --cert=api.crt --key=api.key -n openshift-config

oc patch apiserver cluster --type=merge -p '{"spec":{"servingCerts":{"namedCertificates":[{"names":["api.cluster.domain"],"servingCertificate":{"name":"api-cert"}}]}}}'

---
# 7. LDAP

oc create configmap ldap-ca --from-file=ca.crt=ldap-ca.pem -n openshift-config

oc create secret generic ldap-secret --from-literal=bindPassword=PASSWORD -n openshift-config

oc apply -f oauth-cluster.yaml

---
# 8. TROUBLESHOOTING

## API Down
curl -k https://api.cluster.domain:6443/healthz
oc get pods -n openshift-kube-apiserver

## ETCD
oc get pods -n openshift-etcd
oc logs -n openshift-etcd <pod>

## Ingress
oc get pods -n openshift-ingress
oc describe pod <router-pod>

## Node NotReady
oc describe node <node>
journalctl -u kubelet

---
# 9. HEALTH CHECK NOC

oc get co
oc get nodes
oc adm top nodes
oc get events --sort-by=.lastTimestamp | tail -20

---
# FINE RUNBOOK
