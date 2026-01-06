# Macula Marketplace

Decentralized marketplace client for the Macula mesh platform.

## Overview

Macula Marketplace is an **edge application** that:
- Subscribes to DHT PubSub events for artifact updates
- Maintains a local SQLite index for fast querying (works offline)
- Provides a LiveView UI for browsing and publishing artifacts
- Manages UCAN license tokens for capability-based authorization

## Architecture

The marketplace is **ephemeral** - it exists as event streams in the mesh DHT PubSub system, not as a centralized database. Any mesh participant can maintain a read model by subscribing to marketplace topics.

```
┌─────────────────────────────────────────────────────────────────────┐
│                      MACULA MARKETPLACE                             │
├─────────────────────────────────────────────────────────────────────┤
│  Browser UI (LiveView)                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │   Browse    │  │   Publish   │  │  Licenses   │                 │
│  └─────────────┘  └─────────────┘  └─────────────┘                 │
├─────────────────────────────────────────────────────────────────────┤
│  Domain Layer                                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Artifacts.Index     - SQLite read model for fast queries   │   │
│  │  Mesh.Publisher      - Emit artifact events to mesh         │   │
│  │  Mesh.Subscriber     - Consume events, update local index   │   │
│  │  Licensing.UCAN      - Create/verify capability tokens      │   │
│  │  Licensing.CRLCache  - Track revoked licenses               │   │
│  └─────────────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────┤
│  Infrastructure                                                      │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐           │
│  │    SQLite     │  │  Macula Mesh  │  │  Macula NIFs  │           │
│  │  (Local DB)   │  │  (DHT PubSub) │  │ (UCAN/Crypto) │           │
│  └───────────────┘  └───────────────┘  └───────────────┘           │
└─────────────────────────────────────────────────────────────────────┘
```

## Development

```bash
cd system
mix deps.get
mix ecto.setup
mix phx.server    # http://localhost:4000
```

## DHT PubSub Topics

| Topic | Event | Purpose |
|-------|-------|---------|
| `io.macula.marketplace.artifact_published` | ArtifactPublished | New artifact available |
| `io.macula.marketplace.artifact_updated` | ArtifactUpdated | Version/metadata change |
| `io.macula.marketplace.artifact_deprecated` | ArtifactDeprecated | End-of-life notice |
| `io.macula.marketplace.artifact_revoked` | ArtifactRevoked | Security/license revocation |
| `io.macula.marketplace.license_revoked` | LicenseRevoked | License revocation (CRL) |

## Artifact Types

- **Container** - Docker/OCI container images (ghcr.io)
- **ONNX Model** - ONNX neural network models
- **TWEANN Genome** - TWEANN genome files
- **Dataset** - Training/inference datasets
- **BEAM Release** - Erlang/Elixir releases
- **Helm Chart** - Kubernetes Helm charts

## Offline Capability

The marketplace works offline by maintaining a local SQLite index. When reconnecting to the mesh, use the refresh mechanism to sync missed events:

```elixir
# Request state refresh from any marketplace service
MaculaMarketplace.Mesh.Subscriber.request_refresh()
```

## UCAN Licensing

License tokens use the UCAN (User Controlled Authorization Network) format:
- Capability-based authorization
- Delegation chains for sub-licensing
- Offline verification (no central authority needed)
- Revocation via CRL (Certificate Revocation List) gossip

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_PATH` | SQLite database path | `./marketplace.db` |
| `SECRET_KEY_BASE` | Phoenix secret (64+ chars) | - |
| `MACULA_BOOTSTRAP_PEERS` | Mesh bootstrap URL | `https://boot.macula.io:443` |
| `MACULA_REALM` | Realm in reverse domain | `io.macula` |
| `MACULA_OFFLINE` | Disable mesh (true/false) | `false` |

## License

Apache-2.0
