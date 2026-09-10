# Configuration Notes

The two folders in this project, `ap/` and `ep/`, configure an HTCondor Access Point and Execution Point
to run simulataneously as Slurm jobs on a Slurm cluster. The AP is based on `bin/make-ap-from-tarball` from
the non-root HTCondor installation instructions, while the EP is based on the configuration provided by
`htcondor annex create`. Additional configuration is applied on top of these baselines to make the deployments
robust to a Slurm environment, where either the AP or its EPs could be rescheduled to a different worker node.

# CLI Tool Configuration

## Shared Filesystem Installation

To enable communication between htcondor CLI tools on the Slurm head node and an AP on a worker node,
we install the AP's config files into a shared filesystem accessible by both. 

* CLI tools on the head node are pointed at the AP by sourcing the installed `condor.sh` on the shared FS.
* `start.sh` writes the AP's `NETWORK_HOSTNAME` to the shared config dir to point CLI tools at the right node.
  * This is removed and re-written on each restart to prevent a new instance of the AP from copying the old instance's hostname.

## IDToken Auth

FS auth does not work from the head node to an AP's worker node. We mint a READ/WRITE IDToken into the 
shared config dir in `start.sh` so that CLI tools on the head node can authenticate to the AP.

# AP Configuration

## Daemon Name Pinning

By default, AP Daemon names are derived from the `FULL_HOSTNAME` of the node that the AP is currently running on.
To ensure that AP daemon names and IDToken trust domains remain consistent across reschedulings, we set the following
explicitly:

* `TRUST_DOMAIN`: Subject domain of IDTokens that the AP accepts
* `ANNEX_TOKEN_DOMAIN`: EP subject domain checked in the start expressions of annex jobs.
* `SCHEDD_NAME`: Name of the AP's schedd. Used by annex EPs to locate the schedd for direct connect.

## Force IDToken Auth

Annex jobs' start expression require that an EP have an `AuthenticatedIdentity` matching `<submitter>@<annex token domain>`.
In the scenario that an EP schedules onto the same worker node as its AP, it may attempt FS auth by default, and get an
incorrect identity. We force IDToken auth from the EP to the AP by setting the following:

```
AP_COLLECTOR.SEC_DEFAULT_AUTHENTICATION_METHODS = IDTOKENS
SCHEDD.SEC_DEFAULT_AUTHENTICATION_METHODS = IDTOKENS
```

We also need to grant DAEMON permissions to the IDToken's custom subject to allow schedd direct connect
and ccb registry, since it's not allowed for this subject by default:

```
AP_COLLECTOR.ALLOW_DAEMON = $(ALLOW_DAEMON), ...
SCHEDD.ALLOW_DAEMON = $(ALLOW_DAEMON), ...
```

# EP Configuration

## Explicit IDToken Creation

The EP IDToken minted via `htcondor annex create` (which shells out to `condor_token_fetch`) is insufficient 
to authorize an EP in this setup. Since the CLI tools on the login node authenticate to the AP via `READ/WRITE` 
IDToken auth, the IDToken minted by `annex create` is only scoped to `READ/WRITE` instead of the necessary 
`ADVERTISE_STARTD`/`ADVERTISE_MASTER` scopes needed by an EP. As such, we explicitly mint an
appropriately scoped token for our EP on launch.

```
IDENTITY="$(whoami)@$(condor_config_val ANNEX_TOKEN_DOMAIN)"
condor_token_create -key AP -identity "$IDENTITY" \
    -authz READ -authz WRITE -authz ADVERTISE_STARTD -authz ADVERTISE_MASTER -authz DAEMON
```

## AP Address Polling

Since the AP may move between nodes as its slurm job is resubmitted, running Annex EPs must continually
poll the AP's schedd address file to keep up to date with its address. The `update-annex-collector.sh`
script is configured as a startd cron to accomplish this. It takes the AP's schedd address file on the 
shared filesystem as input, then, once per minute:

* Parses the schedd address file for the current schedd name and machine name.
* Sets `ANNEX_PILOT_COLLECTOR` and `ANNEX_PILOT_SCHEDD_NAME` in a new ep-specific config file.
* Sends a reconfig to the EP's condor_master via SIGHUP.
