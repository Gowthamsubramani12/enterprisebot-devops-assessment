Part 5 – Written Question

Q1. A platform is running around 40 Ingress objects on ingress-nginx, which has reached end-of-life. You need to migrate to the Kubernetes Gateway API with no downtime. Outline your approach, the order you would do things in, and what you expect to break along the way.
Answer
Objective

Migrate approximately 40 existing Ingress resources from the deprecated NGINX Ingress Controller to the Kubernetes Gateway API while ensuring zero downtime, minimal operational risk, and a straightforward rollback strategy.

Phase 1 – Assessment and Planning

Before making any changes, I would perform a complete inventory of the current environment.

This includes:

Export all existing Ingress resources.
Identify all domains, TLS certificates, and backend services.
Document NGINX-specific annotations.
Identify custom rewrite rules, authentication, rate limiting, canary routing, and sticky sessions.
Verify Kubernetes version supports Gateway API CRDs.
Review traffic patterns and business-critical applications.

Goal: Understand what features depend on ingress-nginx and what needs to be migrated.

Phase 2 – Prepare the New Platform

Deploy the Gateway API alongside the existing ingress-nginx controller rather than replacing it.

Activities include:

Install Gateway API CRDs.
Deploy a Gateway controller (for example Envoy Gateway or another supported implementation).
Create Gateway resources.
Configure GatewayClass.
Import TLS certificates.
Validate DNS and networking configuration.

At this stage, ingress-nginx continues serving all production traffic.

Phase 3 – Convert Configuration

Instead of migrating all 40 applications simultaneously, migrate incrementally.

For each application:

Convert Ingress resources into HTTPRoute resources.
Validate routing.
Verify TLS termination.
Test redirects and rewrite rules.
Validate authentication and authorization.
Verify session persistence if required.

Testing should occur in a staging environment before production.

Phase 4 – Progressive Traffic Migration

Traffic migration should be gradual.

Recommended approach:

Route 5% of traffic to Gateway API.
Monitor application metrics.
Increase to 25%.
Increase to 50%.
Increase to 100%.

During migration monitor:

HTTP 4xx and 5xx errors
Response latency
Gateway logs
Application logs
CPU and memory utilization
Client experience

If issues occur, immediately direct traffic back to ingress-nginx.

Phase 5 – Validation

After all services are migrated:

Verify all 40 applications are reachable.
Validate TLS certificates.
Verify health checks.
Test API endpoints.
Confirm monitoring and logging are functioning.
Execute smoke tests and regression tests.

Once production has remained stable for several days, decommission ingress-nginx.

Risks and Expected Challenges

Potential migration issues include:

NGINX annotations not supported by Gateway API.
URL rewrite behavior changes.
Authentication middleware differences.
TLS certificate configuration errors.
DNS propagation delays.
Incorrect HTTPRoute matching.
Differences in load-balancing behavior.
Sticky session incompatibilities.
Monitoring dashboards requiring updates.
Existing CI/CD pipelines needing modification.
Rollback Strategy

A rollback plan must be prepared before production migration.

If issues are detected:

Redirect traffic back to ingress-nginx.
Keep Gateway API resources deployed but inactive.
Investigate logs and metrics.
Fix configuration.
Retry migration during a maintenance window if necessary.

Because both controllers run simultaneously, rollback can be completed within minutes without application downtime.

Architecture Overview
                     Users
                       │
               ┌──────────────┐
               │   DNS / LB   │
               └──────┬───────┘
                      │
        ┌─────────────┴─────────────┐
        │                           │
        ▼                           ▼
 ┌────────────────┐         ┌─────────────────┐
 │ ingress-nginx  │         │ Gateway API     │
 │ (Existing)     │         │ (New Platform)  │
 └──────┬─────────┘         └────────┬────────┘
        │                            │
        └──────────────┬─────────────┘
                       ▼
               Kubernetes Services
                       │
               Application Pods
Conclusion

A successful migration should prioritize zero downtime, incremental rollout, continuous monitoring, and easy rollback. Running the Gateway API alongside the existing ingress-nginx controller minimizes business risk, allows comprehensive validation before cutover, and ensures production traffic is not interrupted during the migration. This phased approach provides a controlled transition while maintaining service availability and reducing operational impact.