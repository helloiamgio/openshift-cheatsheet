
# 🧠 Prometheus Cheatsheet – Kubernetes / OpenShift (WR & Produzione)

Cheatsheet operativo per troubleshooting rapido in produzione (WR / incident).
Tutte le query **escludono i namespace di sistema** (`kube-*`, `openshift-*`).

---

## 🎯 Filtro standard namespace applicativi

```promql
namespace!~"kube-.*|openshift-.*"
```

---

## 🔥 CPU

### CPU usage per pod
```promql
sum by (namespace,pod) (
  rate(container_cpu_usage_seconds_total{
    namespace!~"kube-.*|openshift-.*",
    container!="",container!="POD"
  }[5m])
)
```

### CPU usage vs limit (rischio throttling)
```promql
(
  sum by (namespace,pod)(
    rate(container_cpu_usage_seconds_total{
      namespace!~"kube-.*|openshift-.*"
    }[5m])
  )
)
/
(
  sum by (namespace,pod)(
    container_spec_cpu_quota{
      namespace!~"kube-.*|openshift-.*"
    } / container_spec_cpu_period
  )
)
```

### CPU throttling (evento certo)
```promql
rate(container_cpu_cfs_throttled_seconds_total{
  namespace!~"kube-.*|openshift-.*"
}[5m])
```

---

## 🧠 MEMORIA

### Memory usage per pod
```promql
container_memory_working_set_bytes{
  namespace!~"kube-.*|openshift-.*",
  container!="",container!="POD"
}
```

### Memory usage vs limit (rischio OOM)
```promql
container_memory_working_set_bytes{
  namespace!~"kube-.*|openshift-.*"
}
/
container_spec_memory_limit_bytes{
  namespace!~"kube-.*|openshift-.*"
}
```

### OOMKilled – stato attuale
```promql
kube_pod_container_status_last_terminated_reason{
  namespace!~"kube-.*|openshift-.*",
  reason="OOMKilled"
}
```

### OOMKilled – storico (24h)
```promql
increase(
  kube_pod_container_status_last_terminated_reason{
    namespace!~"kube-.*|openshift-.*",
    reason="OOMKilled"
  }[24h]
)
```

---

## 🔁 RESTART / CRASHLOOP

### Restart per pod
```promql
increase(
  kube_pod_container_status_restarts_total{
    namespace!~"kube-.*|openshift-.*"
  }[15m]
)
```

---

## 🌐 RETE

### Traffico OUT per pod
```promql
sum by (namespace,pod)(
  rate(container_network_transmit_bytes_total{
    namespace!~"kube-.*|openshift-.*"
  }[5m])
)
```

### Traffico IN per pod
```promql
sum by (namespace,pod)(
  rate(container_network_receive_bytes_total{
    namespace!~"kube-.*|openshift-.*"
  }[5m])
)
```

### Spike di rete (batch / sync)
```promql
max_over_time(
  rate(container_network_transmit_bytes_total{
    namespace!~"kube-.*|openshift-.*"
  }[1m])[1h:]
)
```

---

## 💾 STORAGE / FILESYSTEM

### Scritture filesystem per pod
```promql
rate(container_fs_writes_bytes_total{
  namespace!~"kube-.*|openshift-.*"
}[5m])
```

### Letture filesystem per pod
```promql
rate(container_fs_reads_bytes_total{
  namespace!~"kube-.*|openshift-.*"
}[5m])
```

### I/O elevato (job / DB / export)
```promql
rate(container_fs_writes_bytes_total{
  namespace!~"kube-.*|openshift-.*"
}[1m])
+
rate(container_fs_reads_bytes_total{
  namespace!~"kube-.*|openshift-.*"
}[1m])
```

### PVC capacity vs usage
```promql
kubelet_volume_stats_used_bytes{
  namespace!~"kube-.*|openshift-.*"
}
/
kubelet_volume_stats_capacity_bytes{
  namespace!~"kube-.*|openshift-.*"
}
```

### PVC quasi full (>80%)
```promql
(
  kubelet_volume_stats_used_bytes{
    namespace!~"kube-.*|openshift-.*"
  }
/
  kubelet_volume_stats_capacity_bytes{
    namespace!~"kube-.*|openshift-.*"
  }
) > 0.8
```

---

## 🕒 JOB / CRONJOB

### Job completati
```promql
kube_job_status_succeeded{
  namespace!~"kube-.*|openshift-.*"
}
```

### Job falliti
```promql
kube_job_status_failed{
  namespace!~"kube-.*|openshift-.*"
}
```

### Pod short-lived (firma job)
```promql
count_over_time(
  kube_pod_container_status_running{
    namespace!~"kube-.*|openshift-.*"
  }[15m]
) < 15
```

---

## 📊 STATO GENERALE

### Pod non Ready
```promql
kube_pod_status_ready{
  namespace!~"kube-.*|openshift-.*",
  condition="false"
}
```

### Numero pod per namespace
```promql
count by (namespace)(
  kube_pod_info{
    namespace!~"kube-.*|openshift-.*"
  }
)
```

---
## 📊 CAPACITY

### Utilizzo reale di CPU sui nodi (media mobile a 5 minuti, escluso idle)
```promql
cluster:node_cpu:ratio_rate5m{cluster=""}
```

### Percentuale di CPU richieste dai pod rispetto alle CPU allocabili del cluster
```promql
sum(namespace_cpu:kube_pod_container_resource_requests:sum{cluster=""}) 
/ sum(kube_node_status_allocatable{job="kube-state-metrics",resource="cpu",cluster=""})
```

### Percentuale di CPU limits impostati dai pod rispetto alle CPU allocabili del cluster
```promql
sum(namespace_cpu:kube_pod_container_resource_limits:sum{cluster=""}) 
/ sum(kube_node_status_allocatable{job="kube-state-metrics",resource="cpu",cluster=""})


sum(:node_memory_MemAvailable_bytes:sum{cluster=""}) / sum(node_memory_MemTotal_bytes{job="node-exporter",cluster=""})
sum(namespace_memory:kube_pod_container_resource_requests:sum{cluster=""}) / sum(kube_node_status_allocatable{job="kube-state-metrics",resource="memory",cluster=""})
sum(namespace_memory:kube_pod_container_resource_limits:sum{cluster=""}) / sum(kube_node_status_allocatable{job="kube-state-metrics",resource="memory",cluster=""})
```

### CPU Usage per nodo worker (media su 5m)
```promql
100 * avg(rate(node_cpu_seconds_total{mode!="idle", instance=~".*worker.*"}[5m])) by (instance)
  / avg(count(node_cpu_seconds_total{mode="idle", instance=~".*worker.*"}) by (instance))
```

### CPU Requests per nodo worker
```promql
100 *
sum by (node) (
  kube_pod_container_resource_requests{resource="cpu", unit="core"}
  * on(namespace, pod) group_left(node)
  kube_pod_info{node=~".*worker.*"}
)
/
sum by (node) (
  kube_node_status_allocatable{resource="cpu", unit="core", node=~".*worker.*"}
)
```

### CPU Limits per nodo worker
```promql
100 * sum(kube_pod_container_resource_limits{resource="cpu", unit="core"}) by (node)
  / sum(kube_node_status_allocatable{resource="cpu", unit="core"}) by (node)
```

### RAM usata per nodo worker
```promql
100 * (1 - (sum(node_memory_MemAvailable_bytes{instance=~".*worker.*"}) by (instance)
  / sum(node_memory_MemTotal_bytes{instance=~".*worker.*"}) by (instance)))
```

### RAM Requests per nodo worker
```promql
100 * sum(kube_pod_container_resource_requests{resource="memory", unit="byte"}) by (node)
  / sum(kube_node_status_allocatable{resource="memory", unit="byte"}) by (node)
  and on(node) kube_node_status_allocatable{node=~".*worker.*"}
```

### RAM Limits per nodo worker
```promql
100 * sum(kube_pod_container_resource_limits{resource="memory", unit="byte"}) by (node)
  / sum(kube_node_status_allocatable{resource="memory", unit="byte"}) by (node)
  and on(node) kube_node_status_allocatable{node=~".*worker.*"}
```

### RAM disponibile per scheduling (requests)
```promql
(
  sum(kube_node_status_allocatable{resource="memory", unit="byte", node=~".*worker.*"}) by (node)
  -
  sum(kube_pod_container_resource_requests{resource="memory", unit="byte", node=~".*worker.*"}) by (node)
) / 1024 / 1024 / 1024
```

### CPU disponibile per scheduling (requests)
```promql
(
  sum(kube_node_status_allocatable{resource="cpu", unit="core", node=~".*worker.*"}) by (node)
  -
  sum(kube_pod_container_resource_requests{resource="cpu", unit="core", node=~".*worker.*"}) by (node)
)
```

### % MAX/AVERAGE Memory:
```promql
avg_over_time(instance:node_memory_utilisation:ratio{job="node-exporter"}[30d])*100
max_over_time(instance:node_memory_utilisation:ratio{job="node-exporter"}[30d])*100
```

### % MAX/AVERAGE CPU:
```promql
avg_over_time(instance:node_cpu_utilisation:rate1m{job="node-exporter"} [30d]) * 100
max_over_time(instance:node_cpu_utilisation:rate1m{job="node-exporter"} [30d]) * 100
```

### % RAM DISPONIBILE
```promql
(node_memory_MemAvailable_bytes{instance=~".*worker.*"} / node_memory_MemTotal_bytes{instance=~".*worker.*"}) * 100
```

### % CPU DISPONIBILE
```promql
100 * (
  sum by (instance) (rate(node_cpu_seconds_total{mode="idle", instance=~".*worker.*"}[5m]))
  /
  sum by (instance) (rate(node_cpu_seconds_total{instance=~".*worker.*"}[5m]))
)
```

### CPU REQUEST TOTALE NODI WORKER
```promql
sum(
  kube_pod_container_resource_requests{resource="cpu", unit="core"}
  * on(node) group_left(role)
    kube_node_role{role="worker"}
)
```

### RAM REQUEST TOTALE NODI WORKER
```promql
sum(
  kube_pod_container_resource_requests{resource="memory", unit="byte"}
  * on(node) group_left(role)
    kube_node_role{role="worker"}
) / 1024^3
```


### CPU USATA TOTALE NODI WORKER
```promql
sum(
  rate(container_cpu_usage_seconds_total{container!="", container!="POD", pod!=""}[5m])
  * on(namespace, pod) group_left(node)
    kube_pod_info
  * on(node) group_left(role)
    kube_node_role{role="worker"}
)
```


### RAM USATA TOTALE NODI WORKER
```promql
sum(
  container_memory_working_set_bytes{container!="", container!="POD", pod!=""}
  * on(namespace, pod) group_left(node)
    kube_pod_info
  * on(node) group_left(role)
    kube_node_role{role="worker"}
) / 1024^3
```

---

## 🧾 Nota operativa WR

> In caso di incidente, partire sempre da:
> CPU → Memoria → Restart → Rete → Storage → Job  
> e correlare **spike + eventi** per identificare la root cause.

---
