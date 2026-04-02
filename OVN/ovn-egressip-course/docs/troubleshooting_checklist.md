# Checklist rapida troubleshooting EgressIP intermittente

## 1. Stato oggetto EgressIP
```bash
oc get egressip -o yaml
oc describe egressip <NOME>
```

## 2. Nodo che porta l'EgressIP
```bash
oc get nodes -L k8s.ovn.org/egress-assignable
```

## 3. Network operator config
```bash
oc get network.operator cluster -o yaml
```

## 4. Salute OVN
```bash
oc get co/network -o json | jq '.status.conditions[]'
oc get pods -n openshift-ovn-kubernetes -o wide
oc get events -n openshift-ovn-kubernetes --sort-by=.lastTimestamp | tail -100
```

## 5. Pod specifici
```bash
oc describe pod -n openshift-ovn-kubernetes <ovnkube-node-pod>
oc get pod -n openshift-ovn-kubernetes <ovnkube-node-pod> -o json | jq '.status.containerStatuses[]'
```

## 6. Log
```bash
oc logs -n openshift-ovn-kubernetes <pod> -c ovn-controller --since=4h
oc logs -n openshift-ovn-kubernetes <pod> -c ovnkube-controller --since=4h
oc logs -n openshift-ovn-kubernetes <pod> -c nbdb --since=4h
oc logs -n openshift-ovn-kubernetes <pod> -c sbdb --since=4h
oc logs -n openshift-ovn-kubernetes <pod> -c northd --since=4h
```

## 7. Test corretto
```bash
oc exec -n <ns> <pod> -- curl -s https://ifconfig.me
```

## 8. Sospetto principale
Se il toggle label aiuta solo temporaneamente e i readiness probe di `ovnkube-node` vanno in timeout, il problema è probabilmente instabilità OVN/nodo/reachability.
