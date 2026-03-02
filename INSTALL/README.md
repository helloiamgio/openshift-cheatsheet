
# OpenShift Container Platform 4.14
# RUNBOOK OPERATIVO – NOC READY (FULL COMMANDS)
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

wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.18.*/openshift-install-linux.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.18.*/openshift-client-linux.tar.gz

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
# FINE RUNBOOK INSTALLAZIONE
---
# OpenShift 4.x on vSphere (IPI) -- Definitive Network & Load Balancer Runbook

## Cluster Reference Example

-   Cluster Name: ocp01-prod
-   Base Domain: agositafinco.it
-   Machine Network: 10.98.118.0/24
-   API VIP: 10.98.118.50
-   Ingress VIP: 10.98.118.51

------------------------------------------------------------------------

# 1. Architecture Overview

API VIP (10.98.118.50) - TCP 6443 → Kubernetes API - TCP 22623 → Machine
Config Server (bootstrap phase)

Ingress VIP (10.98.118.51) - TCP 80 → Worker nodes - TCP 443 → Worker
nodes

------------------------------------------------------------------------

# 2. DNS Requirements (Must Exist BEFORE Installation)

## Required Records

api.ocp01-prod.agositafinco.it → 10.98.118.50
api-int.ocp01-prod.agositafinco.it → 10.98.118.50
\*.apps.ocp01-prod.agositafinco.it → 10.98.118.51

## Validation

dig api.ocp01-prod.agositafinco.it dig
api-int.ocp01-prod.agositafinco.it dig
test.apps.ocp01-prod.agositafinco.it

------------------------------------------------------------------------

# 3. Load Balancer (F5) Configuration

## API VIP -- 10.98.118.50

Type: - Layer 4 TCP - SSL Passthrough - No SSL offload - No HTTP profile

### Ports Required

-   6443 (Kubernetes API)
-   22623 (Machine Config Server)

### Bootstrap Phase Pool Members

Initially include: - bootstrap_IP:6443 - bootstrap_IP:22623

After masters are created, add: - master1_IP:6443 - master2_IP:6443 -
master3_IP:6443 - master1_IP:22623 - master2_IP:22623 - master3_IP:22623

After installation completes: - Remove bootstrap from pool

------------------------------------------------------------------------

## Ingress VIP -- 10.98.118.51

Ports: - 80 → worker nodes - 443 → worker nodes

------------------------------------------------------------------------

# 4. Firewall Rules

## Nodes → API VIP

Source: 10.98.118.0/24 Destination: 10.98.118.50 Ports: TCP 6443, TCP
22623

## Admin Network → API VIP

Destination: 10.98.118.50 Port: TCP 6443

## Nodes → vCenter

Destination: agsvcs001.agositafinco.it Port: TCP 443

## Nodes → Internet or Proxy

If proxy: TCP 3128 If direct: TCP 443 outbound

## Intra-cluster Communication

Allow full TCP/UDP between nodes.

------------------------------------------------------------------------

# 5. Installation Timeline -- What Happens When

## Phase 1 -- Before Running Installer

-   DNS records created
-   VIP created on F5
-   Ports 6443 and 22623 active
-   Firewall rules applied
-   VIP reachable via nc test

## Phase 2 -- Start Installation

-   Bootstrap VM is created
-   Add bootstrap IP to API VIP pool (6443 & 22623)
-   Verify VIP:22623 reachable

## Phase 3 -- Masters Created

-   Masters receive IPs (DHCP or static)
-   Add master IPs to API VIP pool
-   Bootstrap still remains in pool during install

## Phase 4 -- Bootstrap Complete

When installer reports "Bootstrap complete": - Remove bootstrap from
pool - Only masters remain in API VIP pool

------------------------------------------------------------------------

# 6. Critical Validation Before Setup

nc -zv 10.98.118.50 6443 nc -zv 10.98.118.50 22623 nc -zv 10.98.118.51
443

All must respond before starting installation.

------------------------------------------------------------------------

# 7. Common Installation Failures

-   No route to host → VIP not reachable
-   22623 connection refused → LB misconfiguration
-   x509 unknown authority → Missing vCenter CA trust
-   Bootstrap timeout → api-int DNS missing or incorrect

------------------------------------------------------------------------

# End of Runbook

