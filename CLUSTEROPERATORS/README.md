# OpenShift Cluster Operators

Questo documento elenca tutti i principali **Cluster Operators** (`oc get co`) di OpenShift, descrivendo:
1. **Funzione principale**  
2. **Namespace utilizzato**

| **Operator** | **Funzione principale** | **Namespace utilizzato** |
|---------------|--------------------------|---------------------------|
| authentication | Gestisce il sistema di autenticazione OpenShift (OAuth, login, identity providers). | `openshift-authentication`, `openshift-authentication-operator` |
| baremetal | Gestisce il provisioning di nodi bare metal tramite Ironic (solo in ambienti bare metal). | `openshift-machine-api` |
| cloud-controller-manager | Sincronizza risorse Kubernetes con i provider cloud (es. AWS, GCP, Azure). | `openshift-cloud-controller-manager` |
| cloud-credential | Gestisce le credenziali cloud necessarie ad altri operatori per interagire con l’infrastruttura. | `openshift-cloud-credential-operator` |
| cluster-autoscaler | Scala automaticamente i nodi del cluster in base al carico (MachineSet). | `openshift-machine-api` |
| config-operator | Gestisce la configurazione globale del cluster (feature gates, proxy, immagini, ecc.). | `openshift-config-operator` |
| console | Fornisce la console web di OpenShift. | `openshift-console`, `openshift-console-operator` |
| control-plane-machine-set | Gestisce la configurazione dei nodi di controllo (control plane HA). | `openshift-machine-api` |
| csi-snapshot-controller | Gestisce gli snapshot dei volumi persistenti (CSI driver). | `openshift-cluster-storage-operator` |
| dns | Gestisce CoreDNS e la risoluzione DNS interna del cluster. | `openshift-dns`, `openshift-dns-operator` |
| etcd | Gestisce il datastore etcd che conserva lo stato del cluster Kubernetes. | `openshift-etcd`, `openshift-etcd-operator` |
| image-registry | Fornisce e gestisce il registro interno delle immagini (integrato con build e s2i). | `openshift-image-registry` |
| ingress | Gestisce gli ingress controller (basati su HAProxy) per il traffico HTTP/HTTPS. | `openshift-ingress`, `openshift-ingress-operator` |
| insights | Raccoglie dati di telemetria e diagnostica da inviare a Red Hat Insights. | `openshift-insights` |
| kube-apiserver | Gestisce i pod dell’API server Kubernetes. | `openshift-kube-apiserver` |
| kube-controller-manager | Esegue i controller core di Kubernetes (ReplicaSet, Namespace, ecc.). | `openshift-kube-controller-manager` |
| kube-scheduler | Gestisce la pianificazione dei pod sui nodi. | `openshift-kube-scheduler` |
| kube-storage-version-migrator | Migra le versioni delle risorse persistenti quando vengono aggiornati gli API group. | `openshift-kube-storage-version-migrator` |
| machine-api | Gestisce le macchine (MachineSet, MachineDeployment, scaling automatico). | `openshift-machine-api` |
| machine-approver | Approvazione automatica dei certificati kubelet (CSR) dei nuovi nodi. | `openshift-cluster-machine-approver` |
| machine-config | Applica le configurazioni del sistema operativo sui nodi (MachineConfig, ignition). | `openshift-machine-config-operator` |
| marketplace | Gestisce l’OperatorHub, da cui installare operator tramite OLM. | `openshift-marketplace` |
| monitoring | Implementa Prometheus, Alertmanager, Grafana e gestisce il monitoraggio cluster. | `openshift-monitoring`, `openshift-user-workload-monitoring` |
| network | Configura e gestisce il CNI (es. OVN-Kubernetes, SDN) e le policy di rete. | `openshift-network-operator` |
| node-tuning | Applica profili di ottimizzazione delle performance (tuned). | `openshift-cluster-node-tuning-operator` |
| openshift-apiserver | API server OpenShift specifico (route, project, template, ecc.). | `openshift-apiserver` |
| openshift-controller-manager | Esegue i controller specifici di OpenShift (route, image, quota, ecc.). | `openshift-controller-manager` |
| openshift-samples | Installa gli esempi di template e imagestream predefiniti (per sviluppatori). | `openshift-cluster-samples-operator` |
| operator-lifecycle-manager | Gestisce la vita degli operator (installazione, aggiornamento, rimozione). | `openshift-operator-lifecycle-manager` |
| operator-lifecycle-manager-catalog | Gestisce i cataloghi delle sorgenti degli operator. | `openshift-marketplace` |
| operator-lifecycle-manager-packageserver | Fornisce il servizio API per i pacchetti operator (parte di OLM). | `openshift-operator-lifecycle-manager` |
| service-ca | Gestisce i certificati per i servizi interni del cluster. | `openshift-service-ca` |
| storage | Gestisce il provisioning dinamico dello storage (CSI drivers, StorageClass, PVC). | `openshift-cluster-storage-operator` |

---

📘 **Nota:**  
Alcuni operator possono comparire o meno a seconda della piattaforma (es. *baremetal*, *cloud-controller-manager*).  
Puoi verificarne lo stato con:
```bash
oc get co
```
