# ADR-001: Hub-Spoke Topology Over Azure Virtual WAN

## Context

We need a network topology for an enterprise Azure landing zone that supports:
- Centralized network security (firewall, inspection)
- Hybrid connectivity (VPN/ExpressRoute to on-premises)
- Workload isolation across environments (prod, staging, shared-services)
- Full Terraform manageability with no portal dependencies

Two primary options exist in Azure:

1. **Hub-Spoke with Azure Firewall** — traditional VNet-based model with explicit peering
2. **Azure Virtual WAN (vWAN)** — Microsoft-managed routing fabric with integrated hubs

## Decision

**We chose hub-spoke (option 1)** over Azure Virtual WAN.

## Consequences

### Positive
- **Full Terraform control**: Every resource (VNet, peering, route table, firewall) is an explicit Terraform resource with predictable lifecycle management. No "magic" behind the scenes.
- **Transparent routing**: UDRs and peering flags are explicit and auditable. We can explain every packet path in an interview or architecture review.
- **Cost control**: Hub-spoke uses standard VNets and Azure Firewall — no Virtual WAN hub hourly charges ($0.25/hr/hub + connection unit fees).
- **Granular customization**: We control subnet sizing, NSG placement, route table association, and peering flags independently. vWAN abstracts much of this away.


### Negative (What We Gave Up)
- **No automatic any-to-any routing**: In vWAN, all connected VNets can route to each other automatically. In hub-spoke, we must explicitly manage peering and UDRs for each spoke — more Terraform code, more maintenance.
- **Manual BGP route management**: vWAN handles BGP route propagation from on-premises automatically across all spokes. In hub-spoke, we must configure gateway transit flags and UDRs manually.
- **Scaling friction**: Adding a new spoke requires new peering resources, new UDRs, and firewall rule updates. vWAN makes this declarative. For 50+ spokes, vWAN wins operationally.
- **No built-in SD-WAN integration**: vWAN natively integrates with SD-WAN appliances (Cisco, Fortinet, etc.) for branch connectivity. Hub-spoke requires manual NVA deployment.
- **No automatic hub redundancy**: vWAN hubs are zone-redundant by design. Our hub VNet firewall needs explicit availability zone configuration.

### When We Would Reconsider
- If the organization has **50+ spokes** or **multi-region hubs** — vWAN's operational simplicity would outweigh the cost and abstraction trade-offs.
- If **SD-WAN branch connectivity** is a core requirement — vWAN's native integrations avoid NVA complexity.
- If the team **lacks deep networking expertise** — vWAN's managed routing reduces misconfiguration risk.

## References
- [Azure Virtual WAN documentation](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about)
- [Hub-spoke topology in Azure](https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)
- [Virtual WAN pricing](https://azure.microsoft.com/en-us/pricing/details/virtual-wan/)
