# pg-streaming-replication

PostgreSQL 16 synchronous streaming replication setup using Docker and Vagrant.

## Architecture

```
┌─────────────────┐        WAL stream        ┌─────────────────┐
│   pg-primary    │ ───────────────────────► │   pg-standby    │
│  (read/write)   │                          │   (read-only)   │
└─────────────────┘                          └─────────────────┘
        │                                            │
        └──────────────── pgnet ─────────────────────┘
```

- **pg-primary** — accepts read/write connections, streams WAL to the standby
- **pg-standby** — physical streaming replica, bootstrapped via `pg_basebackup`
- **Synchronous commit** — primary waits for standby acknowledgement before confirming writes (strong durability guarantee)

## Stack

- PostgreSQL 16 (AlmaLinux 9 base image, official PGDG packages)
- Docker + Docker Compose
- Vagrant + libvirt (Fedora 42 VM)

## Requirements

- [Vagrant](https://www.vagrantup.com/) with the `vagrant-libvirt` plugin
- libvirt / KVM on the host

## Getting Started

```bash
git clone https://github.com/<your-username>/pg-streaming-replication.git
cd pg-streaming-replication
vagrant up
```

Vagrant will provision a Fedora 42 VM, install Docker, and start both containers automatically.

### Verify replication

Connect to the primary and check standby status:

```bash
vagrant ssh
docker exec -it pg-primary psql -U postgres -c "SELECT application_name, state, sync_state FROM pg_stat_replication;"
```

Connect to the standby and confirm it is streaming:

```bash
docker exec -it pg-standby psql -U postgres -c "SELECT status, sender_host, write_lag, flush_lag, replay_lag FROM pg_stat_wal_receiver;"
```

## Configuration

| Variable | Default | Description |
|---|---|---|
| `POSTGRES_PASSWORD` | `postgres` | Superuser password (primary) |
| `PG_REPLICATION_USER` | `replicator` | Replication user |
| `PG_REPLICATION_PASSWORD` | `replicator` | Replication user password |
| `PG_STANDBY_NAME` | `standby1` | Must match `synchronous_standby_names` on primary |
| `PRIMARY_HOST` | `pg-primary` | Hostname the standby connects to |

## Design Notes

- `scram-sha-256` is enforced for all connections (no `md5` or `trust` over the network)
- `initdb -k` enables data page checksums to detect silent corruption
- The primary performs a socket-only temporary start during initialisation — no network exposure while creating the replication user
- The standby healthcheck queries `pg_stat_wal_receiver` to verify actual WAL streaming, not just that the process is alive
- Synchronous replication means writes on the primary will hang if the standby is unavailable — this is a deliberate durability tradeoff
