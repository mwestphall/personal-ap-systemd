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

# Download HTCondor

To install an HTCondor Access Point on your Linux host as an unprivileged user, perform the following steps:

* Select a location on your Slurm Cluster's shared filesystem to place your HTCondor configuration files.

* Download the latest version of HTCondor, or a specific development version.

## Shared Filesystem

Regardless of installation method, you must download HTCondor to a location where it will be accessible to your
Slurm worker nodes. This tutorial assumes a shared filesystem at `$SHARED_FS`. Set this variable as appropriate
for your use-case.

```
$ export SHARED_FS=/path/to/shared/fs
$ cd $SHARED_FS
```

## Latest HTCondor 

HTCondor is available for download via `get.htcondor.org`:

```
$ curl -fsSL https://get.htcondor.org | /bin/bash -s -- -download
```

This will download the latest release of HTCondor as a tarball file `condor.tar.gz` in your working directory.

## Specific HTCondor 

To install a specific HTCondor version, `curl` a distro-specific tarball from `https://htcss-downloads.chtc.wisc.edu/tarball`, eg.
(for Alma/Rocky Linux 9):

```
$ curl -o condor.tar.gz -L \
  https://htcss-downloads.chtc.wisc.edu/tarball/25.x/25.15.15/snapshot/condor-25.15.15-x86_64_AlmaLinux9-stripped.tar.gz
```


# Download Slurm Scripts

The Slurm scripts used to provision a cluster are available from [this repository](https://github.com/mwestphall/personal-ap-systemd).
Clone this repo via Git before proceeding.

```
$ git clone https://github.com/mwestphall/personal-ap-systemd
```



# Schedule an Access Point on your Slurm Cluster

The provided [ap.sub](./ap.sub) and [install.sh](./install.sh) scripts launch a Slurm job that:

1. Unpacks the HTCondor tarball from the previous step.

1. Configures HTCondor to run as an Access Point in single-user mode under your Unix account.

1. Creates configuration that points HTCondor command line tools invoked from the login 
   node at your running AP job.


To launch an AP Slurm job:

1. Submit `ap.sub` via `sbatch`, setting your desired Slurm partition, condor tarball location, and shared FS working dir 
   as appropriate:

    ```
    $ cd $SHARED_FS/personal-ap-systemd/ap
    $ sbatch -p <partition name> ap.sub $SHARED_FS/condor.tar.gz $SHARED_FS
    ```

1. Tail the created job's log to confirm that the AP starts successfully.

    ```
    $ tail -f personal-ap.debug
    ...
    ==> To interact with this AP, source the condor env file at $SHARED_FS/condor-1234/condor.sh:
        '. $SHARED_FS/condor-1234/condor.sh'
    ==> Running HTCondor AP in the foreground
    ```
  

1. Source the htcondor configurtion file as noted in the AP's start logs to point the login node's htcondor CLI tools
   at the AP:

    ```
    $ . $SHARED_FS/condor-1234/condor.sh
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

1. Confirm that your AP's annex collector is running.
    ```
    $ condor_status -pool $(condor_config_val NETWORK_HOSTNAME):9618?sock=ap_collector -any
    MyType             TargetType         Name                                     
    
    Collector          None               My Pool - hpc-worker100.slurm.cluster@hpc-worker100.slurm.cluster
    Scheduler          None               hpc-worker100.slurm.cluster
    Submitter          None               you@hpc-worker100.slurm.cluster
    ```

# Submit your first HTCondor Job to your AP

Your Access Point (AP) configured in the previous section manages your HTCondor job queue.
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
echo "I am running on $(hostname)"
sleep 30
EOF

$ chmod +x hello.sh
```

## Submit your HTCondor Job to your AP

Submit a test job to your AP: Mark it to run on an annex (another Slurm worker within the cluster) 
via `--annex-name`:

```
$ htcondor job submit hello.sub --annex-name <annex name>
```

`<annex name>` should be a unique string describing the purpose of your annex.

# Schedule an Execution Point on your Slurm Cluster

Additional resources are required to to run jobs placed into your AP's queue. 
An Execution Point (EP) runs multiple HTCondor jobs within the lifecycle 
of a single Slurm job.

## Prepare an HTCondor Tarball for your Execution Point 

Create an EP tarball via the `htcondor annex create` tool. This tarball contains an HTCondor installation configured
as an Execution Point that runs jobs from your existing Access Point's job queue.

```
$ htcondor annex create test-annex

Please copy the file annex-test-annex.tar to the HPC system
```

## Schedule an Execution Point

The provided [annex-ep.sub](./annex-ep.sub) contains a Slurm script that launches the EP tarball from the previous step.

Submit `annex-ep.sub` via `sbatch`, setting your desired Slurm partition and EP tarball location as appropriate:

```
$ cd $SHARED_FS/personal-ap-systemd/ep
$ sbatch -p <partition-name> annex-ep.sub <path/to/annex.tar>
```

## Confirm that your Job Runs on the Annex

1. Confirm that your Annex EP has successfully connected your AP, and that your job is running on the Annex:

    ```
    $ htcondor annex status test-annex
    Annex 'test-annex' is established.
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

# Resume an Access Point

The AP configured by `ap.sub` will exit after 4 hours by default. To resume your AP after it exits,
launch a new job out of the existing AP directory with `resume-ap.sub`:

```
$ cd $SHARED_FS/personal-ap-systemd/ap
$ sbatch -p <partition name> reume-ap.sub $SHARED_FS/<existing-ap-condor-dir>
```

EPs launched via `ep/annex-ep.sub` will automatically reconnect to an AP resumed via `ap/resume-ap.sub`
