---
title: Defer internal mTLS / service mesh while the platform is single-host docker-compose
status: accepted
date: 2026-05-23
deciders: team
supersedes:
superseded-by:
---

## Context

The Quebec MSSS TGV self-assessment lists a criterion (S07.02) requiring
authenticated and encrypted communication between internal services. The
literal reading is "mTLS between every service". The platform currently runs
as a single-host docker-compose deployment behind a single Traefik reverse
proxy; inter-service traffic never crosses a network boundary an attacker on
the public internet can reach.

The decision pressure: implement a service mesh (Linkerd / Istio / Consul
Connect) or similar mTLS layer to satisfy the literal criterion, vs. document
the threat model and the compensating controls and defer the mesh until the
deployment topology requires it.

## Decision

Defer internal mTLS / service mesh for now. Document the compensating
controls (isolated docker network, no host-port exposure, Traefik as the
single ingress, host hardening, encrypted volumes) and revisit when the
platform moves to multi-host or multi-cloud.

## Rationale

The threat model the TGV criterion is addressing — an attacker on the same
network as the service — does not exist on a single-host compose deployment
with no exposed service ports. Adding a mesh would introduce real complexity
(certificate rotation, sidecar overhead, observability fragmentation) for
zero additional security benefit at this stage. The criterion is satisfied in
spirit by the compensating controls; the audit will be answered with the
threat-model document.

When the deployment topology changes (second host, public-cloud k8s, separate
data plane), the threat model changes and the deferral expires.

## Alternatives considered

- Linkerd / Istio service mesh — rejected because the operational cost (cert
  rotation, control-plane upgrade, debug complexity) is high and the security
  delta on a single host is nil.
- WireGuard between services — rejected for the same reason on single host;
  worth re-evaluating when multi-host.
- Application-level TLS in each service — rejected as duplicating Traefik's
  termination with no additional protection.

## Consequences

- positive: no service-mesh operational burden, no sidecar overhead, no
  certificate rotation infrastructure to maintain
- negative: TGV criterion S07.02 is answered with compensating controls and
  threat-model documentation rather than literal implementation; an auditor
  who reads the criterion literally will need the documented reasoning
- mitigations: maintain the threat-model document, re-open this decision the
  moment the deployment topology changes, ensure the compensating controls
  (isolated network, single ingress, host hardening) are verified on every
  redeploy
