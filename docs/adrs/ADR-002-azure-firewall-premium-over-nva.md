# ADR-002: Azure Firewall Premium Over Third-Party NVA

## Context

The hub-spoke architecture requires a centralized firewall/inspection point for all spoke egress, inter-spoke traffic, and hybrid connectivity. We evaluated:

1. **Azure Firewall Premium** — Azure-native L3-L7 firewall with TLS inspection, IDPS, and threat intelligence
2. **Third-party Network Virtual Appliance (NVA)** — Palo Alto, Fortinet, Check Point, or similar deployed on Azure VMs

## Decision

**We chose Azure Firewall Premium (option 1).**

## Consequences

### Positive
- **Native Terraform support**: `azurerm_firewall` with `sku_tier = "Premium"` is a single resource. NVAs require VM deployment, image management, HA configuration, and vendor-specific bootstrapping — often 10x the Terraform complexity.
- **Zero infrastructure management**: No VM patching, no OS updates, no license file management. Azure Firewall is a fully managed PaaS service with built-in HA across availability zones.
- **Native Azure integration**: Diagnostic settings flow to Log Analytics natively. Azure Policy can enforce firewall presence. Defender for Cloud understands firewall posture. NVAs are opaque to Azure's management plane.
- **TLS inspection with managed certificates**: Premium SKU supports TLS inspection using an intermediate CA cert we provide — no need to deploy a separate PKI infrastructure. IDPS signatures are auto-updated by Microsoft.
- **Threat intelligence feed**: Microsoft's global threat intelligence feed is integrated and updated automatically. NVAs use vendor-specific feeds requiring separate subscription management.
- **99.99% SLA with AZ deployment**: Azure Firewall across availability zones provides 99.99% SLA without us managing HA pairs, heartbeat mechanisms, or failover scripts.

### Negative (What We Gave Up)
- **Advanced L7 features**: Palo Alto and Fortinet offer deeper application-layer inspection, more granular URL filtering categories, and richer reporting dashboards. Azure Firewall Premium's L7 capabilities are improving but not at feature parity with best-of-breed NVAs.
- **Multi-cloud portability**: Palo Alto Panorama can manage firewall policies across Azure, AWS, GCP, and on-premises. Azure Firewall is Azure-only. For organizations with multi-cloud network policy requirements, this is a significant limitation.
- **Existing team expertise**: If the operations team already has Palo Alto or Fortinet expertise, Azure Firewall requires learning a new policy model. NVA vendors offer certification programs and deeper community support.
- **Advanced SD-WAN integration**: NVA vendors (especially Fortinet) offer integrated SD-WAN capabilities. Azure Firewall has no SD-WAN features — it's purely a firewall.
- **Custom IDPS rules**: Azure Firewall Premium IDPS is signature-based with Microsoft-managed rules. NVAs allow fully custom IPS rule authoring. For organizations with specialized threat detection needs, this matters.
- **Cost at scale**: Azure Firewall Premium costs ~$1.75/hr (~$1,277/month) plus data processing charges ($0.016/GB). A well-sized NVA pair on D-series VMs can be cheaper at high throughput, though operational costs (patching, HA) often negate the savings.

### When We Would Reconsider
- If the organization requires **advanced L7 DPI** (deep packet inspection) beyond what Azure Firewall Premium offers
- If **multi-cloud firewall policy consistency** (single pane of glass across clouds) is a hard requirement
- If the security team has **deep NVA vendor expertise** and strong opinions on their tooling
- If **throughput exceeds 30 Gbps** — Azure Firewall's maximum throughput may require firewall parallelization, where NVA scale-out models may be simpler

## References
- [Azure Firewall Premium features](https://learn.microsoft.com/en-us/azure/firewall/premium-features)
- [Azure Firewall pricing](https://azure.microsoft.com/en-us/pricing/details/azure-firewall/)
- [Azure Firewall vs NVA comparison](https://learn.microsoft.com/en-us/azure/architecture/example-scenario/firewalls/)
