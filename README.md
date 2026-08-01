# Enterprise Bot Cloud Engineer Assessment

## Project Overview

This repository contains the deliverables for the **Enterprise Bot Kubernetes & Helm Troubleshooting Assessment**.

The objective was to diagnose and repair a deliberately broken Helm chart deployed to a local Kubernetes cluster. All issues had to be resolved exclusively within the Helm chart — modifying the container images or the protected cluster-state resources was explicitly prohibited. The assessment evaluated the ability to systematically identify root causes, apply targeted fixes, and verify each correction using standard Kubernetes tooling.

---

## Repository Structure

```
enterprisebot-devops-assessment/
├── FINDINGS.md/
│   ├── FINDINGS.md            # Detailed findings for each issue discovered
│   └── broken-chart/          # The original broken Helm chart (reference copy)
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── _helpers.tpl
│           ├── backend.yaml
│           ├── gateway.yaml
│           ├── metrics.yaml
│           ├── migrate-job.yaml
│           ├── rbac.yaml
│           ├── reporter.yaml
│           └── worker.yaml
├── chart/                     # The corrected Helm chart (fixed version)
│   ├── Chart.yaml
│   ├── .helmignore
│   ├── values.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── configmap.yaml
│       ├── deployment.yaml
│       ├── ingress.yaml
│       └── service.yaml
├── project/
│   └── terraform/             # Terraform infrastructure configuration
├── service/                   # Application source and Dockerfile
│   ├── Dockerfile
│   ├── app.py
│   ├── requirements.txt
│   └── .dockerignore
├── setup.sh                   # Environment bootstrap script
├── ANSWERS.md                 # Written assessment answers
└── README.md                  # This file
```

| Path | Purpose |
|------|---------|
| `FINDINGS.md/FINDINGS.md` | Documents each issue discovered, the investigation steps, root cause analysis, and the fix applied. |
| `FINDINGS.md/broken-chart/` | Preserves the original broken Helm chart for reference and comparison. |
| `chart/` | Contains the corrected Helm chart with all fixes applied. |
| `project/terraform/` | Terraform configuration for infrastructure provisioning. |
| `service/` | Application source code, Dockerfile, and dependencies. |
| `setup.sh` | Bootstraps the local Kubernetes environment (Kind cluster, ingress-nginx, image build, Helm deploy). |
| `ANSWERS.md` | Responses to the written assessment questions. |

---

## How to Run the Assessment

### Prerequisites

Ensure the following tools are installed:

- [Docker](https://docs.docker.com/get-docker/)
- [Kind](https://kind.sigs.k8s.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)

### Bootstrap the Environment

```bash
./setup.sh
```

This script performs the following steps:

1. Validates that all required CLI tools are present.
2. Creates (or reuses) a Kind cluster named `demo`.
3. Installs `ingress-nginx` for ingress routing.
4. Builds the Docker image from the `service/` directory.
5. Loads the built image into the Kind cluster.
6. Deploys the corrected Helm chart using `helm upgrade --install`.
7. Waits for all deployments to reach the `Available` condition.

### Verify Pod Status

```bash
kubectl get pods -n debug-lab
```

All pods should report a `Running` status with `1/1` containers ready. The migration Job should show `Completed`.

### Run the Verification Script

```bash
./scenario.sh verify
```

This script validates that all acceptance criteria are satisfied, including deployment readiness, service connectivity, RBAC permissions, and Job completion.

---

## Verification

The assessment is considered successfully completed when all of the following conditions are met:

| Criterion | Expected State |
|-----------|---------------|
| All Deployments (backend, gateway, worker, reporter, metrics) | `Ready` with all replicas available |
| Migration Job | `Completed` successfully |
| Gateway → Backend connectivity | Gateway health endpoint returns healthy |
| Reporter health | Reporter pod is running and can access the Kubernetes API |
| Verification script | `./scenario.sh verify` exits with zero and all checks pass |

---

## Troubleshooting Summary

The following issues were identified and resolved during the assessment. Each fix was applied exclusively within the Helm chart.

### 1. Backend Listening on the Wrong Port

The application image defaults to port `8081`, but the Kubernetes Service and readiness probe expected port `8080`. The `PORT` environment variable was set to `"8080"` in the chart values to align the application with the expected configuration.

### 2. Readiness Probe Failures

Because the backend was listening on the wrong port, the HTTP readiness probe consistently failed, preventing the pod from entering the `Ready` state. Correcting the port configuration resolved the probe failure.

### 3. Gateway DNS Configuration

The gateway was configured with `BACKEND_URL=http://backend.default.svc:8080`, which resolves to the `default` namespace. The backend service is deployed in the `debug-lab` namespace, so the URL was corrected to `http://backend:8080` to use namespace-local DNS resolution.

### 4. SecurityContext — runAsUser

Pods failed with `CreateContainerConfigError` because the `runAsNonRoot` security policy was set but the container image specified a non-numeric user. Kubernetes could not verify that the user was non-root. Adding `runAsUser: 65532` to the security context provided the explicit numeric UID that Kubernetes requires.

### 5. Resource Requests Exceeding Limits

The metrics deployment defined CPU requests that exceeded CPU limits, which is an invalid configuration that Kubernetes rejects at admission. The resource values were corrected so that requests are strictly less than or equal to limits.

### 6. Worker CrashLoopBackOff — Read-Only Filesystem

The worker pod repeatedly crashed because the security context enforced `readOnlyRootFilesystem: true`, but the application required a writable directory at `/var/cache/app`. An `emptyDir` volume was mounted at that path to provide a writable, ephemeral scratch space without weakening the read-only root filesystem policy.

### 7. RBAC RoleBinding Issue

The reporter pod could not list pods via the Kubernetes API because the RoleBinding referenced a ServiceAccount in the wrong namespace. The `subjects[].namespace` field was updated to use `{{ .Release.Namespace }}` to dynamically resolve to the correct deployment namespace.

### 8. Reporter ServiceAccount Issue

The reporter deployment needed to reference the correct ServiceAccount to inherit the RBAC permissions defined by the Role and RoleBinding. The `serviceAccountName` was set correctly in the deployment spec.

### 9. Helm Template Conflict — Duplicate Template File

A leftover `template.yaml` file in the templates directory caused duplicate Kubernetes resources to be rendered during `helm template`. The obsolete file was removed so that only the intended resources are generated.

### 10. Successful Verification

After applying all fixes, `./scenario.sh verify` passed with all checks returning success. Every deployment reached the `Ready` state, the migration Job completed, and inter-service communication was fully operational.

---

## Resource Requests and Limits

### Backend / Gateway / Reporter / Worker

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 50m | 200m |
| Memory | 64Mi | 128Mi |

### Metrics

| Resource | Request | Limit |
|----------|---------|-------|
| CPU | 100m | 500m |
| Memory | 64Mi | 128Mi |

### Rationale

- **Requests** define the minimum guaranteed resources allocated to each pod by the Kubernetes scheduler. Setting conservative requests ensures that pods are scheduled onto nodes without over-committing cluster capacity.
- **Limits** define the maximum resources a pod may consume. This prevents a single misbehaving workload from exhausting node resources and impacting co-located services.
- These values are appropriate for the lightweight, stateless services used in this assessment. The metrics service is allocated higher CPU limits because metrics collection and aggregation are more compute-intensive than standard API serving.
- In a production environment, resource values would be refined using observability data (e.g., Prometheus metrics and VPA recommendations) to match actual workload profiles.

---

## What I Deliberately Skipped

The following items are expected in a production Kubernetes environment but were intentionally omitted because they fall outside the scope of this troubleshooting assessment.

| Item | Risk of Omission |
|------|-----------------|
| **Horizontal Pod Autoscaler (HPA)** | Workloads cannot scale in response to traffic spikes, increasing the risk of service degradation under load. |
| **PodDisruptionBudget (PDB)** | Node drains and cluster upgrades may simultaneously evict all replicas of a service, causing downtime. |
| **Network Policies** | All pods can communicate freely within the cluster, violating the principle of least privilege and increasing the blast radius of a compromise. |
| **Prometheus Monitoring** | No visibility into resource utilization, error rates, or latency — issues are only detected when users report failures. |
| **Centralized Logging** | Container logs are ephemeral and lost when pods restart, making post-incident analysis difficult or impossible. |
| **TLS Termination** | Traffic between the client and the ingress controller is unencrypted, exposing data in transit to interception. |
| **External Secrets Manager** | Secrets stored as plain Kubernetes Secrets are base64-encoded but not encrypted, creating a security risk for sensitive credentials. |
| **GitOps Deployment (e.g., ArgoCD / Flux)** | Manual deployments are error-prone, lack audit trails, and cannot provide automated drift detection or rollback. |
| **Multi-Node High Availability** | A single-node cluster is a single point of failure; any node issue takes down the entire platform. |
| **CI/CD Automation** | Without automated pipelines, deployments depend on manual execution, increasing lead time and human error. |

---

## Production Readiness Improvements

In a production Kubernetes environment, the following enhancements would be implemented to ensure reliability, security, and operational excellence.

### Scaling & Availability

- **Horizontal Pod Autoscaler (HPA)** — Automatically scale workloads based on CPU, memory, or custom metrics to handle variable traffic patterns.
- **PodDisruptionBudgets (PDB)** — Ensure a minimum number of replicas remain available during voluntary disruptions such as node upgrades and cluster maintenance.
- **Rolling Update Tuning** — Configure `maxUnavailable` and `maxSurge` in deployment strategies to enable zero-downtime releases.
- **Multi-AZ / Multi-Region Deployment** — Distribute workloads across availability zones to tolerate infrastructure failures.

### Health & Resilience

- **Liveness Probes** — Detect and automatically restart containers that enter a deadlocked or unresponsive state.
- **Startup Probes** — Prevent premature liveness probe failures for applications with slow initialization.
- **Readiness Gates** — Integrate with external systems (e.g., load balancers) to ensure traffic is only routed to fully initialized pods.

### Security

- **Network Policies** — Enforce micro-segmentation to restrict pod-to-pod communication to only authorized paths.
- **Secrets Management** — Integrate with an external secrets manager (e.g., HashiCorp Vault, AWS Secrets Manager) to securely inject credentials at runtime.
- **Security Scanning** — Scan container images for known CVEs in CI pipelines using tools such as Trivy or Snyk.
- **Admission Controllers** — Enforce organizational policies (e.g., no privileged containers, required resource limits) using OPA Gatekeeper or Kyverno.
- **Policy Enforcement** — Implement Pod Security Standards (Restricted) across all namespaces.
- **Image Signing** — Use Cosign or Notary to verify image provenance and integrity before deployment.

### Observability

- **Prometheus + Grafana** — Collect and visualize metrics for resource utilization, application performance, and SLA tracking.
- **Distributed Tracing** — Implement OpenTelemetry with Jaeger or Tempo to trace requests across microservices and identify latency bottlenecks.
- **Centralized Logging** — Aggregate logs with a stack such as Loki + Grafana or the EFK stack (Elasticsearch, Fluentd, Kibana) for searchable, persistent log retention.
- **Alerting** — Configure Alertmanager with tiered alerting (warning, critical, page) integrated with PagerDuty or Slack.

### Operations

- **GitOps (ArgoCD / Flux)** — Declarative, Git-driven deployments with automated sync, drift detection, and rollback capability.
- **Backup Strategy** — Use Velero or equivalent to back up cluster state, persistent volumes, and critical configuration.
- **Disaster Recovery** — Maintain documented and tested runbooks for full cluster recovery with defined RTO and RPO targets.
- **Resource Monitoring** — Deploy Vertical Pod Autoscaler (VPA) in recommendation mode to continuously right-size resource requests.

---

## Assumptions

The following assumptions were made during troubleshooting:

1. The Kind cluster and `scenario.sh` script provided a representative local Kubernetes environment for testing.
2. The container image (`docker.io/ebinterview/eb-debug-app:1.0.1`) was treated as immutable — all fixes were applied through Helm chart configuration only.
3. The `cluster-state` resources were treated as read-only and were not modified.
4. The `debug-lab` namespace was the target namespace for all workloads.
5. A single replica per workload was sufficient for assessment purposes.
6. No persistent storage was required; all workloads are stateless.
7. DNS resolution within the cluster follows standard Kubernetes service discovery (`<service>.<namespace>.svc.cluster.local`).

---

## Lessons Learned

This assessment reinforced several critical Kubernetes troubleshooting techniques:

| Tool / Command | Purpose |
|----------------|---------|
| `kubectl describe pod` | Inspect pod events, container status, and probe failures. Essential for identifying scheduling errors, image pull failures, and security context violations. |
| `kubectl logs` | View application-level output to identify runtime errors such as port mismatches and filesystem permission failures. |
| `kubectl get events` | Observe cluster-wide events chronologically to correlate failures across multiple resources. |
| `kubectl auth can-i` | Verify RBAC permissions for specific ServiceAccounts. Critical for debugging API access errors without guessing at policy configuration. |
| `helm template` | Render chart templates locally to detect YAML errors, duplicate resources, and incorrect variable substitution before deploying. |
| `helm upgrade --install` | Idempotent deployment command that creates or updates a release. Combined with `--wait`, it blocks until all resources are ready. |
| `./scenario.sh verify` | Automated acceptance testing to confirm that all fixes are correct and all services are functioning as expected. |

**Key takeaway:** Effective Kubernetes troubleshooting follows a disciplined loop — observe symptoms, inspect events and logs, form a hypothesis, apply a targeted fix, and verify. Resisting the temptation to apply speculative fixes and instead investing time in root cause analysis leads to more reliable and maintainable outcomes.

---

## How I Used AI

Transparency regarding AI usage:

- **Documentation and writing assistant** — AI was used to improve the clarity, grammar, and formatting of written documentation including this README and FINDINGS.md.
- **Concept explanations** — AI was occasionally referenced to clarify Kubernetes concepts during the learning process.
- **All debugging, troubleshooting, and implementation work was completed manually** — every issue was diagnosed using `kubectl`, `helm`, and standard command-line investigation. Each fix was validated against the running cluster before being committed.
- **Every fix was verified** using `kubectl get pods`, `kubectl describe`, `kubectl logs`, `helm upgrade`, and the provided `./scenario.sh verify` script before submission.

AI did not perform any debugging, write any Helm templates, or execute any troubleshooting commands. The assessment was completed through hands-on investigation and manual remediation.

---

## Conclusion

This assessment demonstrates practical proficiency in:

- **Kubernetes troubleshooting** — Diagnosing pod failures, probe misconfigurations, and runtime errors.
- **Helm chart debugging** — Identifying template rendering issues, duplicate resources, and value misconfigurations.
- **RBAC troubleshooting** — Resolving ServiceAccount and RoleBinding namespace mismatches.
- **Container security** — Configuring `securityContext`, `runAsUser`, `readOnlyRootFilesystem`, and ephemeral volume mounts.
- **Service discovery** — Correcting DNS-based inter-service communication across namespaces.
- **Resource management** — Setting appropriate CPU and memory requests and limits for workload stability.
- **Production-oriented thinking** — Identifying gaps between assessment scope and production requirements, and articulating a clear path to production readiness.

All issues were resolved through systematic root cause analysis within the constraints of the assessment, without modifying container images or protected cluster-state resources.
