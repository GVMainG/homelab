---
name: proxmox
description: Use when working with Proxmox VE — managing VMs (vm-db-01, vm-proxy-01), snapshots, backups, networking, LXC containers, or querying the Proxmox API. Triggers on requests involving qm, pct, pvesh, vzdump, the Proxmox web UI, or VM lifecycle operations.
---

# Proxmox VE management

This homelab runs on a Proxmox VE host that manages two VMs:

| VM | IP | Role |
|---|---|---|
| vm-db-01 | 192.168.1.51 | PostgreSQL + Vaultwarden + pgAdmin |
| vm-proxy-01 | 192.168.1.50 | dnsmasq + Nginx Proxy Manager |

## Connecting to Proxmox

Proxmox web UI: `https://<proxmox-host-ip>:8006`

SSH to Proxmox host directly:

```bash
ssh root@<proxmox-host-ip>
```

SSH to a VM from Windows workstation:

```bash
ssh gv@192.168.1.51   # vm-db-01
ssh gv@192.168.1.50   # vm-proxy-01
```

## VM management (qm)

```bash
# List all VMs with status
qm list

# Start / stop / reboot
qm start <vmid>
qm shutdown <vmid>     # graceful
qm stop <vmid>         # force
qm reboot <vmid>

# Show VM config
qm config <vmid>

# Open console (from Proxmox host)
qm terminal <vmid>

# Execute command inside VM without SSH
qm guest exec <vmid> -- bash -c "systemctl status docker"
```

## Snapshots

Snapshots capture the full VM state (disk + RAM optionally). Use before risky changes (upgrades, deploy script changes).

```bash
# Create snapshot
qm snapshot <vmid> <snapname> --description "before upgrading postgres"

# List snapshots
qm listsnapshot <vmid>

# Rollback to snapshot
qm rollback <vmid> <snapname>

# Delete snapshot
qm delsnapshot <vmid> <snapname>
```

Convention for snapshot names: `YYYYMMDD-reason` (e.g., `20260413-before-postgres-upgrade`).

## Backups (vzdump)

Proxmox backups are separate from the application-level PostgreSQL backups in `vm-db-01/backup.sh`. Use vzdump for full VM-level backups.

```bash
# Backup a single VM to local storage
vzdump <vmid> --storage local --mode snapshot --compress zstd

# Backup with specific output dir
vzdump <vmid> --dumpdir /var/lib/vz/dump --compress zstd

# Backup all VMs
vzdump --all --storage local --compress zstd
```

Backup modes:
- `snapshot` — minimal downtime, uses LVM/qcow2 snapshot; preferred
- `suspend` — pauses VM briefly; use if snapshot fails
- `stop` — stops VM during backup; last resort

## Networking

The homelab uses a single Linux bridge (`vmbr0`) on the Proxmox host connected to LAN 192.168.1.0/24.

```bash
# Show current network config on Proxmox host
cat /etc/network/interfaces

# Check bridge members
brctl show vmbr0

# Show VM network interfaces
qm config <vmid> | grep net
```

Static IPs are assigned in the VM OS itself (not via Proxmox DHCP), or via dnsmasq DHCP reservations on vm-proxy-01.

## LXC containers (pct)

If lightweight containers are used instead of full VMs:

```bash
pct list
pct start <ctid>
pct stop <ctid>
pct enter <ctid>       # open shell
pct snapshot <ctid> <snapname>
pct restore <ctid> <backup-file>
```

## Proxmox API (pvesh)

Query Proxmox REST API directly from the host without HTTP:

```bash
# List nodes
pvesh get /nodes

# Get VM status
pvesh get /nodes/<nodename>/qemu/<vmid>/status/current

# Get storage info
pvesh get /nodes/<nodename>/storage

# Start VM via API
pvesh create /nodes/<nodename>/qemu/<vmid>/status/start
```

The REST API is also accessible over HTTPS with an API token:

```bash
curl -s -k \
  -H "Authorization: PVEAPIToken=<user>@pam!<tokenid>=<secret>" \
  https://<proxmox-ip>:8006/api2/json/nodes
```

## Storage

```bash
# List storage
pvesm status

# List contents of a storage
pvesm list local

# Common storage paths
/var/lib/vz/images/    # VM disk images (local storage)
/var/lib/vz/dump/      # vzdump backups
/var/lib/vz/snippets/  # cloud-init snippets
```

## Useful host-level commands

```bash
# Check Proxmox version
pveversion -v

# Check cluster status (even single-node)
pvecm status

# View task log
journalctl -u pvedaemon --since "1 hour ago"

# Watch live VM resource usage
watch -n2 qm list
```

## When adding a new VM

1. Create VM in Proxmox UI or via `qm create` with a cloud-init image
2. Assign static IP in the VM OS or via DHCP reservation in `vm-proxy-01/configs/dnsmasq/`
3. Add DNS entry to `vm-proxy-01/configs/dnsmasq/01-split-dns.conf` if it needs a `*.host.loc` name
4. Create the VM's subdirectory in this repo (e.g., `vm-newname/`) with `deploy.sh`, `sync.sh`, `.env.example`, `docker-compose.yml`
5. Add to `CLAUDE.md` VM table and architecture diagram

## When decommissioning a VM

- Take a final vzdump backup before deleting
- Remove its DNS entry from dnsmasq config and run `sudo bash deploy-dnsmasq.sh` on vm-proxy-01
- Remove its Nginx Proxy Manager host entries
