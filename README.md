# Personal HTCondor Cluster on Slurm

This repository contains instructions for launching a single-user HTCondor cluster on Slurm:
- Creating an HTCondor Submit Node (Access Point) for managing your HTCondor jobs via a long-lived Slurm job.
- Creating Execution Points (EPs) for running your HTCondor jobs, also via Slurm jobs.

# Prerequisites

Before creating your HTCondor cluster, you must have the following:

* Job submission permissions on a Slurm cluster:  
  * Your HTCondor Access Point and its Execution Points run as Slurm jobs.

* Networking enabled among your Slurm worker nodes.
  * Execution Points must be able to initiate a TCP connection to the AP’s listening service (on port 9618 by default),
    and the AP must be able to accept that inbound connection. 
  
* A shared filesystem among your Slurm login node and worker nodes:
  * Interaction with your HTCondor cluster is accomplished via HTCondor command line tools run on your Slurm cluster's login node.
    You must be able to access the HTCondor configuration files provisioned by your AP job from the login node.

* `git` installed on your Slurm cluster's login node.

# Download Slurm Scripts

The Slurm scripts used to provision a cluster are available from [this repository](https://github.com/mwestphall/personal-ap-systemd).
Clone this repo via Git before proceeding.

```
$ git clone https://github.com/mwestphall/personal-ap-systemd
```

# Schedule an Access Point on your Slurm Cluster

The provided [ap.sub](./ap/ap.sub) and [install.sh](./ap/install.sh) scripts launch a Slurm job that:

1. Downloads (if needed) the HTCondor binaries.

1. Configures HTCondor to run as an Access Point in single-user mode under your Unix account.

1. Creates configuration that points HTCondor command line tools invoked from the login 
   node at your running AP job.

To launch an AP Slurm job:

1. Submit `ap.sub` via `sbatch`, setting your desired Slurm partition and shared FS base dir as appropriate:

    ```
    $ cd $SHARED_FS/personal-ap-systemd/ap
    $ sbatch -p <partition name> ap.sub $SHARED_FS
    ```

1. Tail the created job's log to confirm that the AP starts successfully.

    ```
    $ tail -f personal-ap.debug
    ...
    ==> To interact with this AP, source the condor env file at $SHARED_FS/current-ap/condor.sh:
        '. $SHARED_FS/current-ap/condor.sh'
    ==> Running HTCondor AP in the foreground
    ```
  

1. Source the htcondor configurtion file as noted in the AP's start logs to point the login node's htcondor CLI tools
   at the AP:

    ```
    $ . $SHARED_FS/current-ap/condor.sh
    ```

# Confirm that your AP is Running

1. Confirm that your AP's Schedd is running.
    ```
    $ condor_q

    -- Schedd: hpc-worker100.slurm.cluster : <192.168.0.1:9618?... @ 08/28/26 14:11:15
    OWNER BATCH_NAME      SUBMITTED   DONE   RUN    IDLE   HOLD  TOTAL JOB_IDS
    
    Total for query: 0 jobs; 0 completed, 0 removed, 0 idle, 0 running, 0 held, 0 suspended 
    Total for all users: 0 jobs; 0 completed, 0 removed, 0 idle, 0 running, 0 held, 0 suspended
    ```

1. Confirm that your AP's collector is running.
    ```
    $ condor_status -pool $(condor_config_val NETWORK_HOSTNAME):9618?sock=ap_collector -any
    MyType             TargetType         Name                                     
    
    Collector          None               My Pool - hpc-worker100.slurm.cluster@hpc-worker100.slurm.cluster
    Scheduler          None               hpc-worker100.slurm.cluster
    Submitter          None               you@hpc-worker100.slurm.cluster
    ```

# Schedule an Execution Point on your Slurm Cluster

Additional resources are required to to run jobs placed into your AP's queue. 
An Execution Point (EP) runs multiple HTCondor jobs within the lifecycle 
of a single Slurm job.

## Schedule an Execution Point

The provided [annex-ep.sub](./ep/annex-ep.sub) contains a Slurm script that launches the EP tarball from the previous step.

Submit `annex-ep.sub` via `sbatch`, setting your desired Slurm partition and the same base dir used for the AP.

```
$ cd $SHARED_FS/personal-ap-systemd/ep
$ sbatch -p <partition-name> annex-ep.sub $SHARED_FS
```

The provided `annex-ep.sub` script launches an EP in "annex mode", which allows it to connect directly back to your
running AP. 
 * In a non-annex HTCondor installation, a 3rd intermediary daemon is needed to broker connections between
APs and EPs.


# Submit your first HTCondor Job to your AP

Your Access Point (AP) configured in the previous section manages your HTCondor job queue, while the
Execution Point (EP) runs any submitted workloads.

Place a "Hello World" HTCondor job into your AP's job queue.

## Create a "Hello World" Job

Create a "Hello World" job on your login node, consisting of a Submit File (`hello.sub`) and an
executable bash script (`hello.sh`):

```
$ cat << EOF >> hello.sub
executable              = hello.sh

log                     = hello.log
output                  = hello.out
error                   = hello.err

should_transfer_files   = Yes
when_to_transfer_output = ON_EXIT

request_cpus            = 1
request_memory          = 512M
request_disk            = 1G

queue

EOF

$ cat << EOF >> hello.sh
#!/bin/bash
echo "Hello, World!"
echo "I am running on \$(hostname)"
sleep 30
EOF

$ chmod +x hello.sh
```

## Submit your HTCondor Job to your AP

Submit a test job to your AP. EPs launched via `annex-ep.sub` are labelled as `default-annex`. To
schedule an HTCondor job that will run on these EPs, specify their annex name via `--annex-name`:

```
$ htcondor job submit hello.sub --annex-name default-annex
```

## Confirm that your Job Runs on the EP

1. Confirm that your EP has successfully connected to your AP, and that your job is running on the EP:

    ```
    $ htcondor annex status default-annex
    Annex 'default-annex' is established.
    Its oldest established request is about 0.00 hours old and will retire in 3.91 hours.
    There are 1 nodes in the established annex.
    There are 2 CPUs in the established annex, of which 1 are busy.
    1 jobs must run on this annex, and 1 currently are.
    ```

1. Check the output of your job after it finishes:

    ```
    $ cat hello.out
    Hello, World!
    I am running on hpc-worker123
    ```

# Additional Options 

## Resume an Access Point

The AP configured by `ap.sub` will exit after 4 hours by default. To resume your AP after it exits,
submit `ap.sub` again with the same base dir. It detects the existing AP at symlink `$SHARED_FS/current-ap`
and starts it without reinstalling:

```
$ cd $SHARED_FS/personal-ap-systemd/ap
$ sbatch -p <partition name> ap.sub $SHARED_FS
```

EPs launched via `ep/annex-ep.sub` will automatically reconnect to a resumed AP.

To launch a fresh AP, remove the `$SHARED_FS/current-ap` symlink before re-submitting the `ap.sub` job.


# Add Worker Nodes

To run larger workloads on your HTCondor cluster, you can schedule additional EPs onto your Slurm workers by re-running the `annex-ep.sub` script:

```
$ cd $SHARED_FS/personal-ap-systemd/ep
$ sbatch -p <partition-name> annex-ep.sub $SHARED_FS
```

Each invocation of this script will create a new directory under $SHARED_FS, labelled after the EP's Slurm batch ID.
