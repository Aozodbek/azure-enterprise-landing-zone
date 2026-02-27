# Architecture — Azure Enterprise Landing Zone

## Overview

This repository implements a production-grade enterprise Azure landing zone using Terraform. The architecture follows a **hub-spoke network topology** with centralized security, DNS, and hybrid connectivity — the foundational pattern used by organizations running regulated workloads at scale.

This is not a tutorial project. Every configuration choice has a documented rationale, and every trade-off is acknowledged.

## High-Level Architecture

The landing zone consists of four VNets organized in a hub-spoke model with centralized egress and DNS:

![Hub-Spoke Architecture](diagrams/hub-spoke-architecture.md)

```
                    ┌──────────────────────────────────┐
                    │         On-Premises / VPN         │
                    └──────────────┬───────────────────┘
                                   │ VPN/ExpressRoute
                    ┌──────────────▼───────────────────┐
                    │        Hub VNet (10.0.0.0/16)     │
                    │  ┌─────────────────────────────┐  │
                    │  │  Azure Firewall Premium      │  │
                    │  │  • TLS Inspection            │  │
                    │  │  • IDPS (Alert+Deny)         │  │
                    │  │  • Threat Intel Filtering    │  │
                    │  └─────────────────────────────┘  │
                    │  ┌─────────┐  ┌──────────────┐   │
                    │  │ VPN GW  │  │ Private DNS  │   │
                    │  │(toggle) │  │   Zones      │   │
                    │  └─────────┘  └──────────────┘   │
                    │       DDoS Protection Plan        │
                    └──┬──────────┬──────────┬─────────┘
                       │          │          │
              VNet     │   VNet   │   VNet   │
             Peering   │  Peering │  Peering │
                       │          │          │
          ┌────────────▼┐  ┌─────▼──────┐  ┌▼─────────────┐
          │  Production  │  │  Staging   │  │Shared Services│
          │ 10.1.0.0/16 │  │10.2.0.0/16│  │ 10.3.0.0/16  │
          │              │  │            │  │               │
          │• Web Tier    │  │• Web Tier  │  │• Log Analytics│
          │• App Tier    │  │• App Tier  │  │• Key Vault    │
          │• Data Tier   │  │• Data Tier │  │• ACR          │
          │• PE Subnet   │  │• PE Subnet │  │• Defender     │
          └──────────────┘  └────────────┘  └───────────────┘
                 │                │                │
                 └─── All egress forced through ───┘
                      Azure Firewall via UDR
```

## Network Design

### Address Space Allocation

| VNet | CIDR | Purpose | Subnets |
|------|------|---------|---------|
| Hub | 10.0.0.0/16 | Central connectivity, security, DNS | AzureFirewallSubnet, GatewaySubnet, ManagementSubnet, DNSResolverSubnet |
| Production | 10.1.0.0/16 | Production workloads | Web (10.1.1.0/24), App (10.1.2.0/24), Data (10.1.3.0/24), PE (10.1.4.0/24) |
| Staging | 10.2.0.0/16 | Pre-production workloads | Web (10.2.1.0/24), App (10.2.2.0/24), Data (10.2.3.0/24), PE (10.2.4.0/24) |
| Shared Services | 10.3.0.0/16 | Centralized platform services | Tools (10.3.1.0/24), Infrastructure (10.3.2.0/24), PE (10.3.3.0/24) |

**Non-overlapping /16 ranges** ensure each VNet has room to grow without re-addressing. CIDR ranges were chosen to avoid conflict with common on-premises ranges (172.16.0.0/12, 192.168.0.0/16).

### Traffic Flow Patterns

See [Data Flow Patterns](diagrams/data-flow-patterns.md) for detailed diagrams.

| Flow | Path | Inspection |
|------|------|------------|
| Spoke → Internet | Spoke → UDR → Azure Firewall → Internet | TLS inspection + IDPS + Threat Intel |
| Spoke → Spoke | Spoke A → UDR → Azure Firewall → Spoke B | Network rules + logging |
| On-Prem → Spoke | VPN/ER → Hub GW → Firewall → Spoke | Network rules + logging |
| Spoke → PaaS | Spoke → Private Endpoint → PaaS (via Private DNS) | No firewall (private network path) |

**Key decision**: All spoke egress is forced through the hub firewall via UDR (`0.0.0.0/0 → firewall_private_ip`). BGP route propagation is disabled on spoke route tables to prevent on-premises routes from bypassing the firewall. See [ADR-001](adrs/ADR-001-hub-spoke-over-virtual-wan.md).

### Azure Firewall Premium

We deploy the Premium SKU (not Basic or Standard) because the security requirements demand:

- **TLS Inspection**: Decrypt and re-encrypt outbound HTTPS traffic for deep inspection. Uses an intermediate CA certificate stored in Key Vault.
- **IDPS (Intrusion Detection and Prevention)**: Signature-based detection in Alert+Deny mode — actively blocks known exploit patterns.
- **Threat Intelligence Filtering**: Microsoft's global threat intelligence feed with configurable allowlist/denylist.
- **Application and Network Rule Collections**: Granular control over spoke-to-internet and spoke-to-spoke traffic patterns.

See [ADR-002](adrs/ADR-002-azure-firewall-premium-over-nva.md) for why Premium over a third-party NVA.

### Private DNS

See [DNS Resolution Flow](diagrams/dns-resolution-flow.md) for the full resolution sequence.

Private DNS Zones are linked to the Hub VNet. Spokes resolve through VNet peering — no per-spoke zone duplication. Zones are parameterized so additional PaaS zones can be added via a variable list.

| Zone | Target Service |
|------|---------------|
| `privatelink.vaultcore.azure.net` | Key Vault |
| `privatelink.blob.core.windows.net` | Blob Storage |
| `privatelink.file.core.windows.net` | File Storage |
| `privatelink.database.windows.net` | SQL Database |
| `privatelink.azurecr.io` | Container Registry |

### Security Model (NSGs + ASGs)

See [NSG/ASG Security Model](diagrams/nsg-asg-security-model.md) for the full model.

- **Every subnet has an NSG** — no exceptions
- **Application Security Groups (ASGs)** provide intent-based grouping (web-servers, api-servers, db-servers)
- **Rules reference ASGs, not raw IPs** — when a VM joins the web-servers ASG, it automatically inherits the right network rules
- **Default deny-all inbound** with explicit allow rules
- **NSG Flow Logs v2** enabled on all NSGs, shipping to Log Analytics with Traffic Analytics

### DDoS Protection

Azure DDoS Protection Plan (Standard tier) is attached to the Hub VNet. Spokes inherit protection through VNet peering. Diagnostic settings ship DDoS metrics and mitigation logs to Log Analytics.

### Hybrid Connectivity

VPN Gateway (VpnGw2 SKU) and ExpressRoute circuit modules are included as **toggleable placeholders** (`deploy_vpn_gateway = false` by default). The GatewaySubnet is pre-provisioned in the hub. When enabled, gateway transit allows spokes to reach on-premises without additional gateways.

## Module Structure

```
modules/
├── networking/          # Hub, spokes, peering, firewall, DNS, NSGs, routes, DDoS
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── README.md
├── identity/            # RBAC, custom roles, PIM
├── policy/              # Policy definitions, initiatives, assignments
├── monitoring/          # Log Analytics, alerts, Defender
└── security/            # Key Vault, resource locks
```

Each module is self-contained with explicit inputs and outputs. The root `main.tf` composes modules with explicit dependencies.

## Decision Log

All architecture decisions are documented as ADRs in [docs/adrs/](adrs/):

| ADR | Decision |
|-----|----------|
| [ADR-001](adrs/ADR-001-hub-spoke-over-virtual-wan.md) | Hub-spoke over Azure Virtual WAN |
| [ADR-002](adrs/ADR-002-azure-firewall-premium-over-nva.md) | Azure Firewall Premium over third-party NVA |
