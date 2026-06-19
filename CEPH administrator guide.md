# 📘 Ceph Administration and Monitoring Guide

A practical reference for managing Ceph in CBIS environments. Covers common administrative tasks, cluster performance monitoring, troubleshooting, security, and monitoring integration.

> **Last updated:** June 2026 — originally created 2020. Revised to reflect current Ceph releases (Squid 19.2.x / Tentacle 20.2.x) and to add a cheat sheet, troubleshooting guide, RBAC/auditing, and performance tuning sections.

---

## 📚 Table of Contents

1. [Quick Reference Cheat Sheet](#-quick-reference-cheat-sheet)
2. [Prerequisites & Assumptions](#-prerequisites--assumptions)
3. [Architecture Overview](#-architecture-overview)
4. [Getting Started](#-getting-started)
5. [Ceph Administration Tasks](#️-ceph-administration-tasks)
   - [1. Changing Replication Factor](#1-changing-replication-factor)
   - [2. Calculating PG Numbers](#2-calculating-pg-numbers)
   - [3. Modifying PG Values](#3-modifying-pg-values)
   - [4. Pool Details](#4-pool-details)
   - [5. Mapping OSDs to Disks](#5-mapping-osds-to-disks)
   - [6. Restarting an OSD](#6-restarting-an-osd)
   - [7. Admin Sockets (asok)](#7-admin-sockets-asok)
   - [8. Reverting Lost Objects](#8-reverting-lost-objects)
   - [9. Scrubbing PGs](#9-scrubbing-pgs)
   - [10. High Disk Utilization OSDs](#10-high-disk-utilization-osds)
6. [Troubleshooting Guide](#-troubleshooting-guide)
7. [Performance Tuning Best Practices](#-performance-tuning-best-practices)
8. [Access Control, RBAC & Auditing](#-access-control-rbac--auditing)
9. [Monitoring & Alerting Integration](#-monitoring--alerting-integration)
10. [Ceph Monitoring](#-ceph-monitoring)
11. [Real-World Examples & Case Studies](#-real-world-examples--case-studies)
12. [Useful References](#-useful-references)

---

## 🚀 Quick Reference Cheat Sheet

The commands admins reach for most often. All assume an admin keyring is available on the node (see [Prerequisites](#-prerequisites--assumptions)).

### Cluster health & status

```bash
ceph -s                          # one-shot cluster status
ceph -w                          # live/streaming status (watch)
ceph health detail               # expanded health warnings
ceph versions                    # daemon versions across the cluster
ceph mon stat                    # monitor quorum status
ceph fsid                        # cluster ID
```

### Pools & placement groups

```bash
ceph osd pool ls detail                       # all pools + settings
ceph osd pool get <pool> all                   # all settings for one pool
ceph osd pool set <pool> size <n>              # change replication factor
ceph osd pool set <pool> pg_num <n>            # change PG count
ceph osd pool autoscale-status                 # PG autoscaler recommendations
ceph df                                        # pool/cluster capacity usage
rados df                                       # per-pool object/IO stats
ceph pg ls                                     # list PGs and their state
ceph pg <pgid> query                           # detailed PG state/history
```

### OSDs

```bash
ceph osd tree                     # CRUSH tree + OSD up/down status
ceph osd df tree                  # utilization per OSD, sorted by host
ceph osd df                       # utilization per OSD (flat)
ceph osd perf                     # per-OSD commit/apply latency
ceph osd metadata <id>            # hardware/host info for one OSD
ceph osd out <id>                 # mark OSD out (stop receiving data)
ceph osd in <id>                  # mark OSD back in
ceph osd down <id>                # mark OSD down (will be re-marked up if alive)
ceph osd set noout                # prevent auto-out during planned maintenance
ceph osd unset noout              # re-enable auto-out after maintenance
```

### Auth / capabilities

```bash
ceph auth list                                  # all cluster identities + caps
ceph auth get client.admin                      # caps for one identity
ceph auth get-or-create client.<name> <caps>    # create/update a user
ceph auth caps client.<name> <caps>             # change caps on existing user
ceph auth rm client.<name>                      # remove a user
```

### Scrubbing & repair

```bash
ceph pg scrub <pgid>             # light consistency check, one PG
ceph pg deep-scrub <pgid>        # full data check, one PG
ceph pg repair <pgid>            # repair an inconsistent PG
ceph osd set noscrub             # pause light scrubs cluster-wide
ceph osd set nodeep-scrub        # pause deep scrubs cluster-wide
```

### Daemon admin sockets

```bash
ceph daemon osd.<id> config show          # live runtime config for a daemon
ceph daemon osd.<id> perf dump            # live perf counters for a daemon
ceph daemon mon.<id> mon_status           # monitor internal status
```

> 💡 **Tip:** Keep this section bookmarked — it covers ~90% of day-to-day lookups. Everything below explains the *why* and the edge cases.

---

## 🔑 Prerequisites & Assumptions

This guide assumes:

- **Admin node access.** Commands are run from a host with a valid `/etc/ceph/ceph.conf` and an admin (or sufficiently privileged) keyring, typically `/etc/ceph/ceph.client.admin.keyring`. For `cephadm`-managed clusters, commands can also be run inside the shell via `cephadm shell` or `ceph orch` from the bootstrap host.
- **sudo / root** on OSD hosts for service-level actions (e.g., `systemctl restart ceph-osd@<id>`).
- A **multi-node cluster** with separate public and cluster (replication) networks, consistent with typical CBIS deployments.

### Required permissions (capabilities)

Ceph access control is capability-based rather than role-based out of the box. The table below maps common tasks in this guide to the minimum capabilities needed — see [Access Control, RBAC & Auditing](#-access-control-rbac--auditing) for how to create scoped users instead of always using `client.admin`.

| Task | Minimum caps |
|---|---|
| Read cluster status, `ceph -s`, `ceph df` | `mon 'allow r'` |
| List/inspect pools and PGs | `mon 'allow r', osd 'allow r'` |
| Change pool settings (size, pg_num) | `mon 'allow rw', osd 'allow rwx'` |
| OSD in/out/down, set/unset flags | `mon 'allow rw', osd 'allow *'` |
| Scrub / repair PGs | `mon 'allow rw', osd 'allow *'` |
| Mark objects lost (`mark_unfound_lost`) | `mon 'allow *', osd 'allow *'` |
| Manage `ceph auth` entries | `mon 'allow *'` |
| Prometheus/Grafana scraping | dedicated `client.monitoring` (`mon 'allow r', mgr 'allow r'`) |

### Ceph version compatibility

This guide targets command syntax that has been stable since **Luminous (12.x)** unless noted otherwise. Where a command or behavior changed, it's called out inline.

| Codename | Major version | Status as of mid-2026 |
|---|---|---|
| Luminous | 12.x | EOL |
| Mimic | 13.x | EOL |
| Nautilus | 14.x | EOL (introduced PG autoscaler, `ceph.audit.log`) |
| Octopus | 15.x | EOL |
| Pacific | 16.x | EOL |
| Quincy | 17.x | EOL |
| Reef | 18.x | EOL (March 2026) |
| Squid | 19.x | Supported (EOL ~Sept 2026) |
| **Tentacle** | **20.x** | **Current stable** |

Notes:
- **`cephadm` orchestration** (the default deployment/upgrade method since Octopus) changes *how* you restart daemons and apply config in some places — e.g., `ceph orch restart osd.<id>` is preferred over a raw `systemctl` call on cephadm-managed hosts, since cephadm manages the systemd unit names (which include the cluster FSID).
- If your cluster was deployed with **ceph-deploy or ceph-ansible** (common for clusters built around 2020), `systemctl restart ceph-osd@<id>` is correct as originally documented.
- Always confirm your actual running version before following version-specific steps: `ceph versions`.

### Other assumptions

- Pool names referenced throughout (`volumes`, `volumes-fast`) follow the original CBIS convention (OpenStack Cinder-backed pools on SSD and NVMe tiers, respectively). Substitute your own pool names.
- Examples assume a healthy quorum of monitors unless a section is specifically about recovering from quorum loss.
- Destructive operations are flagged with ⚠️ — read the **Risks** notes before running them in production.

---

## 🧭 Architecture Overview

Understanding how a client write travels through the cluster makes every section below easier to reason about.

```
┌──────────────────────────────────────────────────────────────────┐
│                  CLIENT (RBD / RGW / CephFS / librados)          │
└───────────────────────────────┬────────────────────────────────--┘
                                 │ object name hashed
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│  POOL  e.g. "volumes", "volumes-fast"                             │
│  - replicated (size=N) or erasure-coded                          │
│  - owns pg_num / pgp_num                                         │
└───────────────────────────────┬────────────────────────────────--┘
                                 │ hash(object) % pg_num
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│  PLACEMENT GROUPS (PGs)                                          │
│  - logical shards of a pool (the unit of replication/recovery)  │
│  - each PG has an "acting set" of OSDs (1 primary + replicas)   │
└───────────────────────────────┬────────────────────────────────--┘
                                 │ CRUSH map decides which OSDs
                                 ▼
┌──────────────────────────────────────────────────────────────────┐
│  OSDs (Object Storage Daemons)                                  │
│  - one daemon per disk (typically), backed by BlueStore         │
│  - report to monitors; replicate/recover PGs among themselves   │
└───────────────────────────────┬────────────────────────────────--┘
                                 ▼
                    Physical disks (HDD / SSD / NVMe)
```

**Why this matters operationally:**
- Changing **pool size** (replication factor) changes how many OSDs each PG's acting set contains — directly affecting the math in [PG sizing](#2-calculating-pg-numbers).
- **PG count** is the lever between "too few PGs" (uneven data distribution, slow recovery) and "too many PGs" (per-OSD memory/CPU overhead). The autoscaler (Nautilus+) manages this automatically in most cases — see [Modifying PG Values](#3-modifying-pg-values).
- **OSD failures** are absorbed at the PG layer: a PG missing a replica becomes `degraded`; a PG that can't reach any working OSD in its acting set becomes `inactive`. This is the basis for the [Troubleshooting Guide](#-troubleshooting-guide).
- Monitors (mons) and managers (mgrs) aren't in this diagram because they don't sit in the data path — they hold cluster maps and coordinate, which is why mon quorum loss stalls *administrative* operations even though already-mapped I/O can sometimes continue briefly.

---

## 🏁 Getting Started

To begin learning Ceph administration, start with the [10 Commands Every Ceph Administrator Should Know](https://tracker.ceph.com/projects/ceph/wiki/10_Commands_Every_Ceph_Administrator_Should_Know).

---

## ⚙️ Ceph Administration Tasks

### 1. Changing Replication Factor

By default, Ceph pools are set with a replication factor of 3. VNF owners may request a replication factor of 2 to improve I/O performance. Lowering the replication factor reduces redundancy and increases the risk of data loss.

**Steps:**

```bash
# Check current replication settings
sudo ceph osd pool ls detail

# Watch Ceph logs in a new terminal
sudo ceph -w

# Change replication size
sudo ceph osd pool set <pool-name> size 2
```

**Pools of Interest:**

- `volumes`: VMs on SSDs
- `volumes-fast`: VMs on NVMe

⚠️ **Risk note:** `size 2` means a single OSD failure during a rebuild window leaves data with zero redundancy. Set `min_size` deliberately (`ceph osd pool set <pool> min_size 1` only if you explicitly accept I/O continuing with one copy) and budget for faster failure response. See the [migration walkthrough](#migration-example-changing-pool-replication-from-3-to-2) in the case studies section.

---

### 2. Calculating PG Numbers

The number of placement groups (PGs) affects performance. Use the formula:

```
Total PGs = (Number of OSDs × 100) ÷ Replication Factor
```

**Examples:**

- 80 OSDs, size 2 → 4000 → Use 4096 (nearest power of 2)
- 80 OSDs, size 3 → 2667 → Use 2048

🔗 [Placement Group Sizing Guide](https://docs.ceph.com/docs/mimic/rados/operations/placement-groups/)

> Since **Nautilus (14.x)**, the **PG autoscaler** module can compute and apply this for you per-pool. Manual calculation is still worth understanding for capacity planning and for clusters running in `warn`-only autoscaler mode. Check current recommendations with:
> ```bash
> ceph osd pool autoscale-status
> ```

---

### 3. Modifying PG Values

Two related settings control PG count:

- `pg_num` — the number of PGs the pool is divided into.
- `pgp_num` — the number of PGs used for actual placement (data movement). This should generally equal `pg_num`.

```bash
# Increase PG count (do this gradually, not all at once on a large pool)
sudo ceph osd pool set <pool-name> pg_num <new-value>
sudo ceph osd pool set <pool-name> pgp_num <new-value>

# Check progress — splitting PGs triggers data movement
ceph -s
ceph osd pool autoscale-status
```

**When to use manual PG changes vs. the autoscaler:**

| Situation | Recommended approach |
|---|---|
| Greenfield cluster, normal growth | Leave `pg_autoscale_mode` on `on` |
| Large pool that needs a big jump (e.g., after major OSD additions) | Increase `pg_num` in increments (≤ ~256 at a time on big pools) to bound data movement, or set autoscaler to `warn` and apply its recommendation |
| Pool is shrinking / being decommissioned | Set `pg_autoscale_mode off` and reduce manually, or let it drain before deletion |

⚠️ **Risk note:** PG splits/merges move data. Never increase `pg_num` by a large multiple in one step on a production pool — it can saturate the cluster network and spike client latency. Increase incrementally and watch `ceph -s` between steps.

---

### 4. Pool Details

```bash
# Full settings for every pool
ceph osd pool ls detail

# All settings for a single pool (size, pg_num, crush rule, quotas, etc.)
ceph osd pool get <pool-name> all

# Capacity and usage
ceph df
ceph df detail

# Per-pool I/O and object counts
rados df

# Pool-level stats (client I/O, recovery I/O)
ceph osd pool stats <pool-name>
```

Useful individual lookups:

```bash
ceph osd pool get <pool-name> size
ceph osd pool get <pool-name> min_size
ceph osd pool get <pool-name> pg_num
ceph osd pool get <pool-name> crush_rule
```

---

### 5. Mapping OSDs to Disks

```bash
# CRUSH hierarchy with host/rack placement and up/down state
ceph osd tree

# Hardware + host metadata for a given OSD (device path, host, etc.)
ceph osd metadata <osd-id>

# On the OSD host: list logical volumes managed by ceph-volume
sudo ceph-volume lvm list

# Cross-check with the kernel's view of block devices
lsblk
df -h /var/lib/ceph/osd/ceph-<osd-id>

# Cluster-wide device inventory (health, vendor, predicted failure where available)
ceph device ls
ceph device get-health-metrics osd.<id>
```

`ceph device ls` is particularly useful for correlating OSD IDs with serial numbers when coordinating physical disk replacement with a datacenter team.

---

### 6. Restarting an OSD

```bash
# 1. Prevent unnecessary rebalancing while you do planned, short restarts
sudo ceph osd set noout

# 2a. Classic (ceph-deploy / ceph-ansible) deployments
sudo systemctl restart ceph-osd@<osd-id>

# 2b. cephadm-managed clusters (preferred — cephadm owns the unit name)
sudo ceph orch daemon restart osd.<osd-id>
# or, from the bootstrap host:
sudo ceph orch restart osd

# 3. Watch recovery/peering settle
ceph -w

# 4. Re-enable normal out-marking once maintenance is done
sudo ceph osd unset noout
```

⚠️ Don't leave `noout` set indefinitely — if you forget to unset it, a *real* OSD failure won't trigger automatic recovery, silently reducing redundancy.

---

### 7. Admin Sockets (asok)

Every Ceph daemon exposes a local Unix admin socket for live introspection and on-the-fly config changes, typically at `/var/run/ceph/<cluster-fsid>/ceph-osd.<id>.asok` (cephadm) or `/var/run/ceph/ceph-osd.<id>.asok` (legacy).

```bash
# View live runtime configuration (reflects any runtime overrides)
ceph daemon osd.<id> config show

# Get/set a single runtime config value without restarting the daemon
ceph daemon osd.<id> config get osd_max_backfills
ceph daemon osd.<id> config set osd_max_backfills 1

# Live performance counters (latency, ops, throughput) for this daemon
ceph daemon osd.<id> perf dump

# Monitor-specific status
ceph daemon mon.<id> mon_status

# List available commands for a daemon
ceph daemon osd.<id> help
```

This is the fastest way to test a tuning change (see [Performance Tuning](#-performance-tuning-best-practices)) on one OSD before rolling it out cluster-wide via `ceph config set`.

---

### 8. Reverting Lost Objects

This is one of the highest-risk operations in Ceph administration — it can mean **permanently and intentionally giving up on data** that the cluster could not otherwise recover. Treat it as a last resort, not a routine fix.

#### How objects become "unfound"

An object becomes unfound when Ceph knows it *should* exist (per PG metadata) but **no currently-reachable OSD has a copy** — typically after multiple, overlapping OSD failures or aggressive maintenance (e.g., wiping/redeploying OSDs that still held the only copy of recently-written data).

#### Step 1 — Identify the problem

```bash
ceph health detail
# Look for: "x/y objects unfound (n%)" on a specific PG

ceph pg ls unfound          # newer releases: PGs with unfound objects in one view
ceph pg <pgid> query        # detailed state; look at "might_have_unfound"
```

The `might_have_unfound` field in the `query` output lists OSDs that *may* still hold a copy — even if they're currently down or out. **This is the single most important field to check before doing anything else.**

#### Step 2 — Try to recover the object before declaring it lost

```bash
# If might_have_unfound lists a down/out OSD, try bringing it back first
sudo ceph osd in <osd-id>
sudo systemctl start ceph-osd@<osd-id>   # or: ceph orch daemon start osd.<id>

# Re-check after the OSD rejoins
ceph pg <pgid> query
```

If the OSD listed in `might_have_unfound` comes back and the object is found, Ceph will recover it automatically — no manual intervention needed. **Always attempt this before using `mark_unfound_lost`.**

#### Step 3 — If recovery isn't possible: choose `revert` or `delete`

```bash
# Option A: revert — roll back to the last known good (previous) version of the object
sudo ceph pg <pgid> mark_unfound_lost revert

# Option B: delete — remove the reference entirely (no prior version available)
sudo ceph pg <pgid> mark_unfound_lost delete
```

| Option | What it does | When to use it |
|---|---|---|
| `revert` | Restores the object to the most recent version Ceph *can* find (which may be slightly stale) | The object had a previous version (e.g., it was an overwrite of existing data) and slightly-stale data is acceptable |
| `delete` | Permanently removes the object/reference; reads will return as if it never existed | The object was net-new (no prior version exists), or staleness is unacceptable and the application can tolerate the object being gone |

⚠️ **Risks:**
- For **RBD-backed volumes** (the common case in CBIS — `volumes`/`volumes-fast`), an unfound object is a chunk of a virtual disk. `revert` can silently roll back a small region of a VM's filesystem to an older state; `delete` can leave a hole that surfaces as filesystem corruption inside the guest. **Coordinate with the VNF/VM owner before running either** — they may need to run `fsck`/application-level consistency checks afterward, or restore from a backup/snapshot instead.
- These commands operate **per-PG**, not per-object — if a PG has multiple unfound objects, the same choice (`revert` or `delete`) applies to all of them in that PG in one invocation.
- There is no undo. Once invoked, the PG's unfound-object state is resolved permanently.

#### Step 4 — If the OSD itself is permanently gone

If the OSD that held the only copy is destroyed (failed disk, wiped host) and will never come back:

```bash
# Tell Ceph to stop waiting on a permanently lost OSD
sudo ceph osd lost <osd-id> --yes-i-really-mean-it
```

This is a separate, narrower acknowledgment than `mark_unfound_lost` — it tells the cluster the OSD itself is gone so PG recovery can proceed without it, which often surfaces the remaining unfound objects you'll then resolve with Step 3.

#### Recovery procedure checklist

1. `ceph health detail` → identify affected PG(s).
2. `ceph pg <pgid> query` → check `might_have_unfound`.
3. Bring back any candidate OSD before doing anything destructive.
4. If truly unrecoverable, notify the data owner / check for snapshots or backups.
5. Choose `revert` vs `delete` based on whether a prior version exists and whether staleness is acceptable.
6. Run `ceph pg <pgid> mark_unfound_lost <revert|delete>`.
7. Re-check `ceph health detail` and `ceph pg <pgid> query` to confirm the PG is now `active+clean`.
8. Document the incident (which objects, which PG, which choice, and why) for postmortem/audit purposes.

---

### 9. Scrubbing PGs

Scrubbing is Ceph's background data-integrity check. **Light scrubs** compare metadata; **deep scrubs** read and checksum actual object data.

```bash
# Trigger a scrub/deep-scrub manually on one PG
ceph pg scrub <pgid>
ceph pg deep-scrub <pgid>

# Same, at the OSD level (scrubs every PG the OSD primaries)
ceph osd scrub <osd-id>
ceph osd deep-scrub <osd-id>

# Pause/resume scrubbing cluster-wide (e.g., during a maintenance window or recovery)
ceph osd set noscrub
ceph osd set nodeep-scrub
ceph osd unset noscrub
ceph osd unset nodeep-scrub

# Repair a PG that scrubbing found inconsistent
ceph pg repair <pgid>
```

Relevant scheduling config (cluster-wide, via `ceph config set osd ...` or `ceph.conf`):

| Setting | Purpose |
|---|---|
| `osd_scrub_begin_hour` / `osd_scrub_end_hour` | Restrict scrubbing to an off-peak window |
| `osd_scrub_load_threshold` | Skip starting new scrubs if host load is above this threshold |
| `osd_deep_scrub_interval` | Maximum time between deep scrubs of a given PG (default 1 week) |
| `osd_scrub_min_interval` / `osd_scrub_max_interval` | Bounds for light scrub frequency |

`ceph pg repair` fixes inconsistencies (mismatched checksums between replicas) found by scrubbing — it is **not** the same operation as resolving unfound objects in Section 8; use `repair` when replicas disagree, and the [Reverting Lost Objects](#8-reverting-lost-objects) procedure when no replica exists at all.

---

### 10. High Disk Utilization OSDs

```bash
# Find the most-utilized OSDs
ceph osd df tree

# Cluster-wide fill thresholds
ceph osd dump | grep -E "full_ratio|backfillfull_ratio|nearfull_ratio"

# Quick fix: reweight OSDs based on current utilization (temporary, until next change)
ceph osd reweight-by-utilization

# More durable fix: adjust CRUSH weight directly
ceph osd crush reweight osd.<id> <new-weight>

# Let the balancer module manage this continuously
ceph balancer status
ceph balancer mode upmap
ceph balancer on
```

**Order of operations when an OSD is approaching `nearfull`:**

1. Confirm it's not a symptom of uneven PG distribution: `ceph osd df tree`.
2. If uneven distribution is the cause, prefer the **balancer module** (`upmap` mode) over manual reweighting — it's self-correcting as the cluster changes.
3. If the *pool* itself is genuinely near capacity (not just unevenly distributed), the real fix is adding OSDs/capacity, not reweighting — reweighting only redistributes existing data, it doesn't create headroom.
4. Use `ceph osd reweight-by-utilization` only as a short-term lever; it can mask whether you actually need more capacity.

---

## 🛠️ Troubleshooting Guide

Each entry follows **Symptom → Diagnosis → Solution**.

### Cluster health is `HEALTH_WARN` or `HEALTH_ERR`

- **Diagnosis:**
  ```bash
  ceph health detail
  ceph -s
  ```
- **Solution:** `health detail` names the specific check that's failing (e.g., `PG_DEGRADED`, `OSD_DOWN`, `MON_CLOCK_SKEW`). Jump to the matching entry below, or to the relevant numbered task above.

### Slow requests / blocked I/O reported by clients

- **Diagnosis:**
  ```bash
  ceph health detail        # look for "slow requests" / "REQUEST_SLOW"
  ceph osd perf             # find OSDs with high commit/apply latency
  ceph daemon osd.<id> dump_blocked_ops
  ```
- **Solution:** Identify the slow OSD(s) from `ceph osd perf` or the blocked-ops dump. Common causes: a failing disk (check `ceph device get-health-metrics`), an overloaded OSD during recovery/backfill (throttle with `osd_recovery_max_active` / `osd_max_backfills`, see [Performance Tuning](#-performance-tuning-best-practices)), or network issues between OSD hosts.

### OSD shows `down` in `ceph osd tree`

- **Diagnosis:**
  ```bash
  ceph osd tree
  ceph osd metadata <id>
  # On the OSD host:
  sudo systemctl status ceph-osd@<id>
  sudo journalctl -u ceph-osd@<id> -n 200
  ```
- **Solution:** Check the daemon log for the actual failure (disk I/O error, OOM, assertion failure). If the disk itself failed, follow the [OSD failure case study](#case-study-recovering-from-an-osd-failure). If it's a transient crash, restart per [Section 6](#6-restarting-an-osd) after setting `noout`.

### PGs stuck in `peering`, `degraded`, `undersized`, or `inactive`

- **Diagnosis:**
  ```bash
  ceph pg dump_stuck inactive
  ceph pg dump_stuck unclean
  ceph pg <pgid> query
  ```
- **Solution:**
  - `peering` stuck → usually means an OSD in the acting set is unreachable; check `ceph osd tree` for down OSDs in that PG's acting set.
  - `degraded` → expected and self-healing after an OSD failure, as long as recovery is progressing (`ceph -s` shows recovery I/O). If it's *not* progressing, check recovery throttling settings and overall cluster load.
  - `inactive` → no OSD in the acting set is currently up; this blocks client I/O to that PG. Restoring any one of the listed OSDs (even temporarily) is the fastest fix.

### OSD(s) at or near `full` / `nearfull` / `backfillfull`

- **Diagnosis:**
  ```bash
  ceph osd df tree
  ceph df
  ```
- **Solution:** See [Section 10](#10-high-disk-utilization-osds). If the *cluster* (not just one OSD) is near capacity, this is a capacity-planning issue, not a rebalancing one — add OSDs/nodes.

### Monitor quorum issues (`ceph -s` hangs or reports no quorum)

- **Diagnosis:**
  ```bash
  ceph mon stat
  ceph quorum_status
  # On each mon host:
  sudo systemctl status ceph-mon@<id>
  ```
- **Solution:** Confirm a majority of mons are reachable on the network (Ceph requires `floor(n/2)+1` mons for quorum). Check for clock skew (`MON_CLOCK_SKEW` in `ceph health detail`) — NTP/chrony drift between mon hosts is a very common cause of quorum flapping.

### Unfound objects reported in `ceph health detail`

- **Diagnosis/Solution:** See [Section 8 — Reverting Lost Objects](#8-reverting-lost-objects) in full; don't skip the `might_have_unfound` check.

### Scrub errors / inconsistent PGs

- **Diagnosis:**
  ```bash
  ceph health detail        # look for "possible data damage: N pg inconsistent"
  rados list-inconsistent-obj <pgid>
  ```
- **Solution:** Run `ceph pg repair <pgid>` (Section 9). If repair fails repeatedly on the same PG, suspect a failing underlying disk on one of that PG's OSDs and check `ceph device get-health-metrics`.

---

## ⚡ Performance Tuning Best Practices

These are starting points, not universal defaults — always validate changes against your own workload before applying cluster-wide.

### Recovery & backfill throttling

Recovery/backfill competes with client I/O. After major events (OSD add/remove, pg_num change), tune how aggressively the cluster heals itself:

```bash
ceph config set osd osd_recovery_max_active 3      # lower = less impact on client I/O, slower healing
ceph config set osd osd_max_backfills 1             # concurrent backfills per OSD
ceph config set osd osd_recovery_op_priority 3      # relative priority vs. client ops (lower = gentler)
```

Raise these temporarily during a low-traffic maintenance window if you need faster recovery and can tolerate the I/O impact.

### BlueStore / OSD memory

```bash
ceph config set osd osd_memory_target 4294967296    # ~4GiB per OSD; tune to available RAM ÷ OSDs-per-host
```

`osd_memory_target` is the primary lever for BlueStore cache sizing — undersizing it on NVMe-heavy hosts is a common cause of avoidable read latency.

### PG count and the balancer

- Keep `pg_autoscale_mode on` unless you have a specific reason not to.
- Run the **balancer module** in `upmap` mode for continuous, low-disruption rebalancing instead of one-off `reweight-by-utilization` calls:
  ```bash
  ceph balancer mode upmap
  ceph balancer on
  ```

### Network

- Use **separate public and cluster (replication) networks** — replication/recovery traffic should not compete with client traffic on the same link.
- Enable jumbo frames (MTU 9000) consistently across all OSD hosts and switches if your network supports it end-to-end; a partial rollout causes silent fragmentation issues.

### Client-side (RBD)

- Enable RBD client-side caching (`rbd cache = true`) for workloads with sequential or bursty write patterns; verify it's compatible with your hypervisor's own caching layer to avoid double-buffering surprises.

### NVMe-specific

- Set `bluestore_min_alloc_size` appropriately for your media (smaller allocation units suit NVMe better than HDD defaults) — check the current default for your Ceph version, since defaults have changed across releases, and test before changing it on an existing OSD (it generally only applies to newly-created OSDs).

### Validate before/after

Always compare before/after with the same tool:

```bash
ceph osd perf
rados bench -p <pool> 60 write --no-cleanup
rados bench -p <pool> 60 seq
```

---

## 🔐 Access Control, RBAC & Auditing

### How Ceph access control actually works

Ceph doesn't have a separate "roles" system like Kubernetes RBAC — access is controlled by **capability strings** attached to a `client.<name>` identity, scoped per-service (`mon`, `osd`, `mgr`, `mds`). You build role-like behavior by defining consistent capability sets and naming conventions.

### Core `ceph auth` commands

```bash
# List every identity and its capabilities
ceph auth list

# Inspect one identity
ceph auth get client.admin

# Create a new identity with specific caps
ceph auth get-or-create client.<name> \
  mon 'allow r' \
  osd 'allow rwx pool=volumes'

# Change caps on an existing identity
ceph auth caps client.<name> mon 'allow r' osd 'allow r pool=volumes'

# Export a keyring for distribution to a client host
ceph auth get client.<name> -o /etc/ceph/ceph.client.<name>.keyring

# Remove an identity
ceph auth rm client.<name>
```

### Suggested role mapping for CBIS admin teams

| Role | Suggested identity | Capabilities |
|---|---|---|
| Read-only auditor / NOC | `client.readonly` | `mon 'allow r', osd 'allow r'` |
| Monitoring system (Prometheus) | `client.monitoring` | `mon 'allow r', mgr 'allow r'` |
| Pool/tenant operator (scoped to specific pools) | `client.<tenant>` | `mon 'allow r', osd 'allow rwx pool=<pool>'` |
| Full cluster admin | `client.admin` | `mon 'allow *', osd 'allow *', mgr 'allow *'` — restrict to a small, named set of people |

**Principle:** avoid distributing `client.admin` broadly. Create scoped identities per team/automation system so that capability and audit trails map to *who* did *what*, not just "admin did something."

### Audit logging

Ceph monitors maintain a dedicated audit log of every administrative command they process — distinct from the general cluster log:

```bash
# Default location on mon hosts
/var/log/ceph/<cluster-name>.audit.log

# Tail it live
sudo tail -f /var/log/ceph/ceph.audit.log

# General cluster log (health changes, OSD up/down events, etc.)
ceph log last 100
ceph -w
```

Recommendations:
- Ship `ceph.audit.log` to your centralized logging stack (rsyslog/ELK/Splunk) rather than relying on local rotation alone — it's your primary record of "which identity ran which `ceph` command, when."
- Combine with shell-level auditing (`auditd`) on admin nodes for full command-line context (the audit log captures the RADOS command, not necessarily the operator's shell session).
- Review the audit log as part of incident postmortems for any destructive operation (e.g., the [unfound-objects procedure](#8-reverting-lost-objects)) — Step 8 of that checklist explicitly calls for this.

---

## 📈 Monitoring & Alerting Integration

The metrics referenced throughout this guide (`ceph osd perf`, `ceph df`, PG states, etc.) are also exposed as time-series metrics for Prometheus/Grafana, which is the recommended way to track them continuously rather than polling manually.

### Enable the built-in Prometheus exporter

```bash
ceph mgr module enable prometheus
```

This exposes metrics on the active mgr at `http://<mgr-host>:9283/metrics` by default. Point your Prometheus `scrape_configs` at that endpoint (and at the standby mgr, since the active mgr can fail over).

### Grafana dashboards

The Ceph project maintains official Grafana dashboards (the "ceph-mixin") covering cluster health, pool/PG status, OSD performance, and host-level metrics:

- Dashboard source & docs: https://docs.ceph.com/en/latest/mgr/dashboard/
- Prometheus module reference: https://docs.ceph.com/en/latest/mgr/prometheus/

### cephadm-managed clusters: built-in monitoring stack

If your cluster is orchestrated with `cephadm`, you can deploy Prometheus, Grafana, Alertmanager, and node-exporter directly via the orchestrator instead of standing them up separately:

```bash
ceph orch apply node-exporter
ceph orch apply prometheus
ceph orch apply alertmanager
ceph orch apply grafana
```

Reference: https://docs.ceph.com/en/latest/cephadm/services/monitoring/

### Suggested alert coverage

At minimum, alert on:
- `HEALTH_WARN` / `HEALTH_ERR` persisting beyond a short grace period (avoid alerting on every transient blip during planned maintenance).
- Any OSD `down` for longer than your expected restart window.
- PGs in `inactive` state (client-impacting) — this should page, not just notify.
- OSD utilization crossing `nearfull_ratio`.
- Mon clock skew.
- Unfound objects (`ceph health detail` showing `OBJECT_UNFOUND`) — should page immediately given the manual judgment call required in [Section 8](#8-reverting-lost-objects).

The Ceph community ships starter Alertmanager rules alongside the cephadm monitoring stack; treat them as a baseline and tune thresholds to your environment.

---

## 📊 Ceph Monitoring

### Health

```bash
ceph health
ceph health detail
```

### Cluster Usage

```bash
ceph df
ceph df detail
rados df
```

### OSD Stats

```bash
ceph osd df tree
ceph osd perf
ceph osd stat
```

### Performance Stats

```bash
ceph daemon osd.<id> perf dump
ceph -w
rados bench -p <pool> 60 write --no-cleanup
```

> See [Monitoring & Alerting Integration](#-monitoring--alerting-integration) above for turning these into dashboards and alerts instead of manual polling.

---

## 🌍 Real-World Examples & Case Studies

### Migration example: Changing pool replication from 3 to 2

**Scenario:** The `volumes-fast` pool (NVMe-backed) is replication factor 3. A VNF owner has requested factor 2 to reduce write amplification and improve latency for a latency-sensitive workload.

**Pre-checks:**
```bash
ceph osd pool get volumes-fast size        # confirm current = 3
ceph osd pool get volumes-fast min_size    # note current min_size
ceph -s                                    # confirm cluster is HEALTH_OK before starting
ceph osd df tree                           # confirm enough free capacity exists post-shrink-of-redundancy expectations don't apply here, but confirm no OSDs are already near-full
```

**Change:**
```bash
ceph osd pool set volumes-fast size 2
```

**Watch the transition:**
```bash
ceph -w
# Expect: a burst of "active+clean" PGs as Ceph drops the third replica;
# this *reduces* data movement compared to growing a pool, since it's
# removing copies rather than creating them.
```

**Post-checks:**
```bash
ceph osd pool get volumes-fast size        # confirm = 2
ceph osd pool get volumes-fast min_size    # confirm this is still sane (commonly 1 or 2 depending on risk tolerance)
ceph -s                                    # confirm HEALTH_OK
ceph df                                    # confirm expected capacity increase (≈33% more usable space at same raw capacity)
```

**Rollback plan:** Replication factor changes are reversible by setting `size` back to 3 (`ceph osd pool set volumes-fast size 3`), which simply tells Ceph to create a third replica again — but note this re-creates real data movement and does **not** undo any data loss risk window that already passed at factor 2. Communicate the reduced-redundancy window to the VNF owner before, not after, the change.

**Outcome documentation:** Record the before/after `size`, `min_size`, the time window of reduced redundancy, and who approved the change — this pairs with the [audit logging](#-access-control-rbac--auditing) guidance above.

### Case study: Recovering from an OSD failure

**Scenario:** `ceph -s` reports `HEALTH_WARN`, and `ceph osd tree` shows `osd.47` as `down`. Alerting fired from the monitoring stack described [above](#-monitoring--alerting-integration).

**1. Triage:**
```bash
ceph osd tree                          # confirm osd.47 is down (and check if also "out")
ceph osd metadata 47                   # identify host and underlying device
ssh <host-of-osd.47>
sudo systemctl status ceph-osd@47
sudo journalctl -u ceph-osd@47 -n 200  # look for the actual failure: I/O error, assertion, OOM
```

Suppose the journal shows repeated I/O errors — a failing physical disk, confirmed via:
```bash
ceph device get-health-metrics osd.47
sudo smartctl -a /dev/<device>
```

**2. Contain:**
```bash
# If not already out, mark it out so the cluster starts healing immediately
ceph osd out 47
```
At this point `ceph -s` should show recovery I/O as the cluster re-replicates the PGs that lost a copy.

**3. Monitor recovery:**
```bash
ceph -w
ceph pg dump_stuck unclean     # should empty out as recovery progresses
```
If recovery is too slow and impacting client I/O, or too aggressive, adjust the throttles from [Performance Tuning](#-performance-tuning-best-practices) (`osd_recovery_max_active`, `osd_max_backfills`).

**4. Replace the hardware:**
```bash
# Once the disk is physically replaced and recovery has completed:
ceph osd purge 47 --yes-i-really-mean-it     # remove the old OSD identity from the cluster maps
# Then provision the new disk as a new OSD, e.g.:
sudo ceph-volume lvm create --data /dev/<new-device>
```

**5. Verify:**
```bash
ceph -s                 # HEALTH_OK
ceph osd tree            # new OSD up and in
ceph osd df tree         # confirm it's receiving its fair share of data (or let the balancer handle it)
```

**6. Postmortem:** Was this an isolated disk failure, or the Nth failure on that batch of drives this quarter? Check `ceph device get-health-metrics` across the fleet for similar SMART trends before they become the next page.

---

## 🔗 Useful References

- [10 Commands Every Ceph Administrator Should Know](https://tracker.ceph.com/projects/ceph/wiki/10_Commands_Every_Ceph_Administrator_Should_Know)
- [Placement Group Sizing Guide](https://docs.ceph.com/docs/mimic/rados/operations/placement-groups/)
- [Ceph Releases Index (versions & EOL)](https://docs.ceph.com/en/latest/releases/)
- [Ceph Troubleshooting OSDs](https://docs.ceph.com/en/latest/rados/troubleshooting/troubleshooting-osd/)
- [Ceph Troubleshooting PGs](https://docs.ceph.com/en/latest/rados/troubleshooting/troubleshooting-pg/)
- [Ceph Manager Prometheus Module](https://docs.ceph.com/en/latest/mgr/prometheus/)
- [cephadm Monitoring Services](https://docs.ceph.com/en/latest/cephadm/services/monitoring/)
- [Ceph User & Capability Management](https://docs.ceph.com/en/latest/rados/operations/user-management/)
- [Ceph Balancer Module](https://docs.ceph.com/en/latest/rados/operations/balancer/)
