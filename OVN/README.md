# OVN-Kubernetes + EgressIP su OpenShift
**Guida completa in italiano**

## 1. Cos'è OVN-Kubernetes

OVN-Kubernetes è il plugin di rete predefinito di OpenShift.  
In pratica:

- Kubernetes/OpenShift definisce **cosa vuoi**: pod, service, network policy, egress IP, ecc.
- OVN-Kubernetes traduce quella volontà in una **rete logica**.
- Open vSwitch (OVS) sul nodo applica davvero il forwarding dei pacchetti.

Detta ancora più semplice:

> Kubernetes descrive l'intenzione.  
> OVN costruisce il modello logico.  
> OVS fa passare davvero i pacchetti.

## 2. Componenti principali

### 2.1 Livello “controllo”
- **Kubernetes / OpenShift API**  
  Fonte degli oggetti: Pod, Namespace, Service, NetworkPolicy, EgressIP, EgressFirewall, EgressQoS.
- **ovnkube-controller**  
  Guarda gli oggetti Kubernetes e crea/aggiorna lo stato logico di rete in OVN.
- **NBDB (northbound database)**  
  Contiene lo stato logico desiderato: router, switch, NAT, policy, load balancer logici.
- **ovn-northd**  
  Compila la configurazione logica del NBDB in logical flows per il SBDB.
- **SBDB (southbound database)**  
  Contiene logical flows e binding verso i nodi/chassis.

### 2.2 Livello “datapath”
- **ovn-controller**  
  Gira su ogni nodo. Legge il SBDB e programma OVS.
- **Open vSwitch (OVS)**  
  È il datapath vero e proprio. Bridge come `br-int` e `br-ex` fanno passare i pacchetti.
- **br-ex**  
  Ponte verso la rete esterna / host primary interface.
- **ovn-k8s-mp0**  
  Interfaccia management usata nella topologia OVN-Kubernetes.

## 3. Immagini

## 3.1 Diagramma semplificato
![OVN control/data plane](../images/custom_ovn_control_data_plane.png)

### 3.2 Flusso EgressIP
![EgressIP flow](../images/custom_egressip_packet_flow.png)

### 3.3 Flowchart troubleshooting
![Troubleshooting](../images/custom_troubleshooting_flow.png)

### 3.4 Diagrammi ufficiali Red Hat
![RH OVN architecture](../images/rh_ovn_architecture.png)

![RH OVN logical architecture](../images/rh_ovn_logical_architecture.png)

## 4. Architettura logica OVN

I componenti logici importanti sono:

- **Logical switch del nodo**
- **`ovn_cluster_router`**
- **`join` switch**
- **Gateway router `GR_<node>`**
- **External switch `ext_<node>`**
- **Pod / logical ports**

Visione mentale utile:

```text
Pod -> Logical switch -> ovn_cluster_router -> join switch -> GR_<node> -> br-ex -> rete esterna
```

## 5. Cos'è EgressIP

L'EgressIP serve a far uscire il traffico di uno o più pod con un **source IP costante** verso servizi **fuori dal cluster**.

Si usa tipicamente quando:
- firewall esterni fanno whitelist di IP;
- database esterni accettano solo alcuni source IP;
- vuoi un IP di uscita stabile per namespace o pod selezionati.

### 5.1 Cose importanti
- EgressIP vale per traffico **verso l'esterno del cluster**
- non è il meccanismo giusto per traffico **east-west**
- `pod -> node IP` non usa EgressIP
- il test va fatto verso un vero target esterno

## 6. Come lavora EgressIP

Un oggetto `EgressIP` lega:
- uno o più IP di uscita;
- un `namespaceSelector`;
- opzionalmente un `podSelector`.

Il traffico dei pod selezionati viene:
1. riconosciuto come matching;
2. instradato logicamente verso un nodo che può ospitare l'EgressIP;
3. sottoposto a **SNAT** sul nodo egress;
4. inviato fuori dal cluster tramite `br-ex` / rete esterna.

## 7. Perché “togliere e rimettere la label” sembra risolvere

Se togli/rimetti una label su namespace o pod, stai forzando:
- rivalutazione dei selector dell'oggetto `EgressIP`;
- riconciliazione OVN;
- eventuale riprogrammazione di policy/NAT/assegnazioni.

Quindi:

> il toggle della label può “sbloccare” temporaneamente il flusso,  
> ma spesso non elimina la causa primaria.

Se poi il problema ricompare, la causa è tipicamente a monte:
- instabilità OVN;
- nodo egress dichiarato down;
- probe / database / controller in timeout;
- rete esterna / ARP / gateway instabili.

## 8. Caso tipico: intermittente, poi reset temporaneo

Sintomo:
- un namespace con EgressIP smette di uscire correttamente;
- togliendo e rimettendo la label torna a funzionare;
- dopo un po' smette di nuovo.

### 8.1 Ipotesi più probabili
1. **match dei selector ballerino**
2. **nodo egress considerato down o non reachabile**
3. **OVN non stabile sul nodo**
4. **problema su `br-ex`, gateway o rete esterna**
5. **test-case non rappresentativo**

## 9. Troubleshooting pratico

## 9.1 Fotografia iniziale

```bash
oc get egressip -o yaml
oc describe egressip <NOME>
oc get nodes -L k8s.ovn.org/egress-assignable
oc get network.operator cluster -o yaml
```

Cosa guardare:
- `status.items`
- nodo che ospita l'EgressIP
- selector
- eventuale `reachabilityTotalTimeoutSeconds`

## 9.2 Verifica salute OVN

```bash
oc get co/network -o json | jq '.status.conditions[]'
oc get pods -n openshift-ovn-kubernetes -o wide
oc get events -n openshift-ovn-kubernetes --sort-by=.lastTimestamp | tail -100
```

Se vedi:
- `Readiness probe failed`
- restart dei container
- timeouts ricorrenti

allora il problema è molto probabilmente **OVN / nodo / DB / controller**.

## 9.3 Pod specifici in errore

```bash
oc describe pod -n openshift-ovn-kubernetes <ovnkube-node-pod>
oc get pod -n openshift-ovn-kubernetes <ovnkube-node-pod> -o json | jq '.status.containerStatuses[]'
```

Guarda soprattutto:
- `ovn-controller`
- `ovnkube-controller`
- `nbdb`
- `sbdb`
- `northd`

## 9.4 Log utili

```bash
oc logs -n openshift-ovn-kubernetes <pod> -c ovn-controller --since=4h
oc logs -n openshift-ovn-kubernetes <pod> -c ovnkube-controller --since=4h
oc logs -n openshift-ovn-kubernetes <pod> -c nbdb --since=4h
oc logs -n openshift-ovn-kubernetes <pod> -c sbdb --since=4h
oc logs -n openshift-ovn-kubernetes <pod> -c northd --since=4h
```

Filtri utili:

```bash
egrep -i 'timeout|probe|reconnect|northbound|southbound|db|leader|raft|egress|assign|reassign|unreach|health'
```

## 9.5 PodNetworkConnectivityChecks

```bash
oc get podnetworkconnectivitychecks -n openshift-network-diagnostics
oc get podnetworkconnectivitychecks -n openshift-network-diagnostics -o yaml
```

Serve per capire se il cluster ha avuto outage o instabilità di reachability.

## 9.6 Test corretto dell'EgressIP

Da un pod selezionato, prova verso un target esterno.

```bash
oc exec -n <ns> <pod> -- curl -s https://ifconfig.me
```

oppure verso un server echo esterno controllato.

Non usare come prova principale:
- node IP
- service interno
- route interna
- altro traffico east-west

## 9.7 Verifica host sul nodo egress

```bash
oc debug node/<node> -- chroot /host ip addr
oc debug node/<node> -- chroot /host ip route
oc debug node/<node> -- chroot /host ip rule
oc debug node/<node> -- chroot /host ip neigh
```

Su shared gateway mode (`routingViaHost: false`) non interpretare `ip_forward=0` come problema automatico.

## 9.8 Ispezione OVN vera

```bash
oc get po -n openshift-ovn-kubernetes
oc rsh -n openshift-ovn-kubernetes -c nbdb <ovnkube-node-pod>
ovn-nbctl show
ovn-nbctl lr-list
ovn-nbctl ls-list
```

Per southbound:

```bash
oc rsh -n openshift-ovn-kubernetes -c sbdb <ovnkube-node-pod>
ovn-sbctl show
```

## 10. Diagnosi ragionata per il caso discusso

Se trovi contemporaneamente:
- `egressIPConfig: {}`
- `Readiness probe failed: command timed out` su più `ovnkube-node`
- problema che si “sistema” con toggle label

la lettura più credibile è:

> la label forza una riconciliazione,  
> ma la causa primaria è un'instabilità OVN/nodo/reachability, non una CR `EgressIP` banalmente errata.

## 11. Tuning possibile: failover timeout

Se il nodo egress è dichiarato down troppo aggressivamente, puoi valutare un tuning del timeout di reachability:

```yaml
spec:
  defaultNetwork:
    ovnKubernetesConfig:
      egressIPConfig:
        reachabilityTotalTimeoutSeconds: 5
```

Usalo con criterio:
- valore troppo basso -> failover rapido ma più sensibile al jitter;
- valore più alto -> meno falsi positivi ma failover più lento.

## 12. Comandi “coltellino svizzero”

### 12.1 Tutto lo stato principale
```bash
oc get egressip -o yaml
oc get nodes -L k8s.ovn.org/egress-assignable
oc get network.operator cluster -o yaml
oc get pods -n openshift-ovn-kubernetes -o wide
oc get events -n openshift-ovn-kubernetes --sort-by=.lastTimestamp | tail -100
```

### 12.2 Describe di tutti gli ovnkube-node
```bash
for p in $(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node -o name); do
  echo "===== $p ====="
  oc describe -n openshift-ovn-kubernetes "$p" | egrep -i 'Node:|Ready:|Unhealthy|Readiness|Last State|State:'
done
```

### 12.3 Log mirati
```bash
for p in $(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
  echo "===== $p ====="
  oc logs -n openshift-ovn-kubernetes "$p" -c ovn-controller --since=4h |     egrep -i 'timeout|probe|reconnect|db|northbound|southbound|egress|assign|unreach' || true
done
```

## 13. Script incluso nel repo

Per raccogliere automaticamente i dati:

```bash
chmod +x scripts/collect-ovn-egressip-diagnostics.sh
./scripts/collect-ovn-egressip-diagnostics.sh
```

Output:
- `network.operator` CR
- `co/network`
- tutti gli `EgressIP`
- label dei nodi
- eventi OVN
- describe dei pod `ovnkube-node`
- log per container

## 14. In sintesi

### OVN in una frase
OVN-Kubernetes è il motore che trasforma gli oggetti di rete di OpenShift in rete logica e poi in regole reali sul datapath OVS.

### EgressIP in una frase
EgressIP ti garantisce un source IP stabile per traffico dei pod verso l'esterno del cluster.

### Diagnosi più probabile nel caso intermittente
Se il toggle delle label “cura” solo temporaneamente e hai timeout sulle readiness probe di `ovnkube-node`, il problema è molto probabilmente nella stabilità di OVN o del nodo, non nel concetto di EgressIP in sé.

## 15. Fonti ufficiali

- Red Hat OpenShift 4.18 — About OVN-Kubernetes  
  https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/ovn-kubernetes_network_plugin/about-ovn-kubernetes

- Red Hat OpenShift 4.18 — OVN-Kubernetes architecture  
  https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/ovn-kubernetes_network_plugin/ovn-kubernetes-architecture-assembly

- Red Hat OpenShift 4.18 — Configuring an egress IP address  
  https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/ovn-kubernetes_network_plugin/configuring-egress-ips-ovn

- Red Hat OpenShift 4.18 — Troubleshooting OVN-Kubernetes  
  https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/ovn-kubernetes_network_plugin/ovn-kubernetes-troubleshooting-sources

- OVN-Kubernetes — Egress IP  
  https://ovn-kubernetes.io/features/cluster-egress-controls/egress-ip/
