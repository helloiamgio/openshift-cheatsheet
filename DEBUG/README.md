# 🧾 Guida Comandi di Debug – OpenShift / RHEL CoreOS (journalctl, crictl & co.)

Questa guida raccoglie i principali comandi utili per il **debug dei nodi OpenShift 4.x**, in particolare nella fase di **bootstrap** o durante problemi runtime con kubelet e CRI-O.

---

## 🔹 Sezione 1 – `journalctl`: analisi dei log di sistema

`journalctl` mostra i log di **systemd**, utili per analizzare errori dei servizi di sistema.

### 📘 Comandi generali

| Comando | Descrizione |
|----------|-------------|
| `journalctl -xe` | Mostra gli ultimi log con dettagli su errori e warning. |
| `journalctl -f` | Segue i log in tempo reale. |
| `journalctl -b` | Log dall’ultimo boot del sistema. |
| `journalctl -k` | Log del kernel. |
| `journalctl --since "10 min ago"` | Log degli ultimi 10 minuti. |
| `journalctl --since yesterday` | Log da ieri. |
| `journalctl --since "2025-11-07 14:00"` | Log da un’ora/data specifica. |
| `journalctl --no-pager` | Mostra tutto senza paginazione. |

---

### 🔍 Log per servizio specifico

| Comando | Descrizione |
|----------|-------------|
| `journalctl -u kubelet` | Log del servizio kubelet. |
| `journalctl -u crio` | Log del container runtime CRI-O. |
| `journalctl -u NetworkManager` | Log del servizio rete. |
| `journalctl -u bootkube.service` | Log del processo bootstrap. |
| `journalctl -u release-image.service` | Log del servizio che scarica e lancia l’immagine release. |
| `journalctl -u ignition` | Log del provisioning tramite Ignition. |
| `journalctl -u systemd-resolved` | Log del resolver DNS locale. |

---

### 🧩 Filtri avanzati

| Comando | Descrizione |
|----------|-------------|
| `journalctl -p err` | Mostra solo messaggi di livello error. |
| `journalctl -p warning` | Mostra warning ed errori. |
| `journalctl -t crio` | Filtra per tag (es. log generati da CRI-O). |
| `journalctl -u kubelet -n 50` | Mostra ultime 50 righe del servizio kubelet. |
| `journalctl -u crio --grep "Failed"` | Cerca nei log la stringa “Failed”. |
| `journalctl -u kubelet -S -1h -U now` | Log kubelet dell’ultima ora. |
| `journalctl _PID=1234` | Log di un processo specifico. |

---

### 📦 Export dei log

| Comando | Descrizione |
|----------|-------------|
| `journalctl -u kubelet > /tmp/kubelet.log` | Esporta log di kubelet. |
| `journalctl --no-pager --all > /tmp/all_logs.txt` | Esporta tutti i log. |
| `journalctl --list-boots` | Mostra i boot precedenti. |
| `journalctl -b -1` | Log del boot precedente. |

---

## 🔹 Sezione 2 – `crictl`: debug container runtime (CRI-O)

`crictl` interagisce direttamente con CRI-O per ispezionare container e pod.

### 📘 Comandi base

| Comando | Descrizione |
|----------|-------------|
| `crictl ps` | Elenca container in esecuzione. |
| `crictl ps -a` | Elenca tutti i container, anche terminati. |
| `crictl images` | Elenca le immagini presenti localmente. |
| `crictl info` | Mostra info generali del runtime. |
| `crictl version` | Versione di client/server CRI-O. |

---

### 🧩 Ispezione e log container

| Comando | Descrizione |
|----------|-------------|
| `crictl inspect <container-id>` | Dettagli JSON di un container. |
| `crictl inspectp <pod-id>` | Dettagli del pod sandbox. |
| `crictl logs <container-id>` | Mostra log stdout/stderr del container. |
| `crictl stats` | Statistiche dei container attivi. |
| `crictl pods` | Elenca i pod sandbox gestiti. |
| `crictl stopp <pod-id>` | Arresta un pod sandbox. |
| `crictl rm <container-id>` | Rimuove un container. |
| `crictl rmp <pod-id>` | Rimuove un pod sandbox. |

---

### ⚙️ Gestione immagini

| Comando | Descrizione |
|----------|-------------|
| `crictl pull quay.io/...` | Pull manuale di un’immagine. |
| `crictl rmi <image-id>` | Rimuove un’immagine locale. |
| `crictl imagefsinfo` | Info sul filesystem delle immagini. |

---

### 🧠 Debug avanzato

| Comando | Descrizione |
|----------|-------------|
| `crictl config runtime-endpoint` | Mostra o imposta il socket runtime. |
| `crictl inspect <id> | grep -i logPath` | Trova percorso log container. |
| `crictl inspectp <pod-id> | jq .status.sandboxID` | Estrae sandbox ID. |
| `crictl exec <container-id> ls /` | Esegue comandi all’interno del container. |
| `crictl ps --name etcd` | Filtra container per nome. |

---

## 🔹 Sezione 3 – `systemctl`: gestione servizi

| Comando | Descrizione |
|----------|-------------|
| `systemctl list-units --type=service` | Elenca servizi attivi. |
| `systemctl restart kubelet` | Riavvia kubelet. |
| `systemctl restart crio` | Riavvia CRI-O. |
| `systemctl enable crio --now` | Abilita CRI-O al boot. |
| `systemctl status crio -l` | Mostra stato esteso di CRI-O. |
| `systemctl cat kubelet` | Mostra file unit systemd di kubelet. |

---

## 🔹 Sezione 4 – Altri strumenti utili

| Strumento | Comando | Descrizione |
|------------|----------|-------------|
| `oc get nodes` | Verifica se il nodo è visibile al cluster. |
| `oc get co` | Stato dei Cluster Operators. |
| `oc describe node <node>` | Dettagli su kubelet e taint del nodo. |
| `podman ps -a` | Elenca container (se CRI-O non parte). |
| `rpm-ostree status` | Mostra versione OS e commit. |
| `nmcli dev show` | Mostra configurazione rete. |
| `ss -tulpn` | Mostra porte TCP/UDP aperte. |

---

## 🔹 Sezione 5 – Troubleshooting rapido

| Caso | Comando | Obiettivo |
|------|----------|-----------|
| Kubelet non si avvia | `journalctl -u kubelet -p err` | Vedere errori recenti. |
| Etcd non parte | `crictl ps -a \| grep etcd` + `crictl logs <id>` | Verifica log etcd. |
| Problema di rete | `journalctl -u NetworkManager -p err` | Errori DHCP/DNS. |
| CRI-O non risponde | `systemctl restart crio` + `journalctl -u crio -b` | Riavvia runtime e analizza log. |
| Container crashloop | `crictl ps -a --name <container>` | Controlla exit code. |
| Bootstrap bloccato | `journalctl -b -u bootkube.service` | Individua punto di blocco. |

---

## 🔹 Sezione 6 – Raccolta log completa

Raccogli log per analisi esterna:

```bash
sos report --all-logs --batch
```

Oppure manualmente:

```bash
tar czf /tmp/bootstrap_debug_logs.tar.gz   /var/log   /etc/kubernetes   /etc/systemd/system   /var/lib/kubelet   /var/lib/containers   /etc/containers
```

---

> 💡 **Suggerimento:** combinare `journalctl`, `crictl` e `systemctl` fornisce un quadro completo del comportamento del nodo e dei container durante il bootstrap.
