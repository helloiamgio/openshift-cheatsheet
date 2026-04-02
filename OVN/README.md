# OVN-Kubernetes + EgressIP su OpenShift
**Mini-corso pratico + troubleshooting guide**  
Lingua: italiano

> Obiettivo: capire cos'è OVN-Kubernetes, come funziona l'EgressIP, dove guardare quando il traffico esce in modo intermittente e perché un toggle delle label può “sistemare” il problema solo temporaneamente.

## Struttura del repo

- `docs/ovn_egressip_course.md` — guida completa
- `images/` — immagini Red Hat ufficiali + diagrammi personalizzati più chiari
- `scripts/collect-ovn-egressip-diagnostics.sh` — raccolta automatica read-only dei principali dati diagnostici

## Anteprima immagini

### Architettura OVN-Kubernetes semplificata
![OVN control/data plane](images/custom_ovn_control_data_plane.png)

### Flusso EgressIP
![EgressIP flow](images/custom_egressip_packet_flow.png)

### Flowchart di troubleshooting
![Troubleshooting](images/custom_troubleshooting_flow.png)

### Diagrammi ufficiali Red Hat
![RH OVN architecture](images/rh_ovn_architecture.png)

![RH OVN logical architecture](images/rh_ovn_logical_architecture.png)

## Per iniziare

Apri direttamente:
- [`docs/ovn_egressip_course.md`](docs/ovn_egressip_course.md)

## Nota rapida sul caso reale

Nel caso discusso, gli indizi più forti sono:
- `egressIPConfig: {}` nel `Network` CR, quindi il cluster usa i default;
- eventi `Readiness probe failed: command timed out` su più `ovnkube-node`;
- comportamento “funziona dopo toggle label, poi ricade”.

Questa combinazione fa pensare più a **instabilità OVN / nodo / reachability** che a una CR `EgressIP` scritta male.
