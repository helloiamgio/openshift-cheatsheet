#!/usr/bin/env bash
set -Eeuo pipefail

OUTDIR="${1:-ovn-egressip-diag-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$OUTDIR"

run() {
  local name="$1"
  shift
  echo "[INFO] collecting: $name"
  {
    echo "### COMMAND: $*"
    echo
    "$@"
  } >"$OUTDIR/$name.txt" 2>&1 || true
}

run network_cr oc get network.operator cluster -o yaml
run network_co oc get co/network -o yaml
run egressip_all oc get egressip -o yaml
run egressip_wide oc get egressip -o wide
run nodes_labels oc get nodes -L k8s.ovn.org/egress-assignable
run ovn_pods oc get pods -n openshift-ovn-kubernetes -o wide
run ovn_events oc get events -n openshift-ovn-kubernetes --sort-by=.lastTimestamp
run podnetwork_checks oc get podnetworkconnectivitychecks -n openshift-network-diagnostics -o yaml

pods=$(oc get pods -n openshift-ovn-kubernetes -l app=ovnkube-node -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' || true)
for p in $pods; do
  safe_name=$(echo "$p" | tr '/' '_')
  run "describe_${safe_name}" oc describe pod -n openshift-ovn-kubernetes "$p"
  containers=$(oc get pod -n openshift-ovn-kubernetes "$p" -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{end}' || true)
  for c in $containers; do
    {
      echo "### LOGS pod=$p container=$c"
      echo
      oc logs -n openshift-ovn-kubernetes "$p" -c "$c" --since=4h || true
    } >"$OUTDIR/log_${safe_name}_${c}.txt" 2>&1
  done
done

cat > "$OUTDIR/README.txt" <<'EOF'
Questa raccolta è read-only.
Punti da correlare:
- quale nodo porta l'EgressIP in status.items
- readiness probe timeout su ovnkube-node
- restart dei container nbdb/sbdb/northd/ovn-controller
- messaggi di reconnect, timeout, southbound/northbound DB
EOF

echo "[OK] Output salvato in: $OUTDIR"
