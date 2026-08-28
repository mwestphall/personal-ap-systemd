# Personal AP SystemD Configuration

This repository contains instructions for installing a single-user HTCondor Access Point (AP) in unprivileged mode,
configuring the AP to run persistently via unprivileged SystemD, and creating personal Execution Points (EP) for
running jobs via your AP on a Slurm Annex.

# Prerequisites

Before installing a personal AP, you must have the following:

* Job submission permissions on a Slurm cluster:  
  Execution points for a personal AP run as Slurm jobs.

* Login access to a Linux host with inbound network traffic from your Slurm cluster:  
  Execution Points must be able to open an incoming TCP connection to your AP.

* Permissions to open a port on your Linux login host.

* `git` installed on your Linux login host.


# Personal AP Install

To install an HTCondor Access Point on your Linux host as an unprivileged user, perform the following steps:

### Download Prerequisites

1. HTCondor is available for download via `get.htcondor.org`:

    ```
    $ cd ~
    $ curl -fsSL https://get.htcondor.org | /bin/bash -s -- -download
    ```

    This will download the latest release of HTCondor as a tarball file `condor.tar.gz` in your home directory.

1. Additional configuration used in this setup is available from the [personal-ap-systemd](https://github.com/mwestphall/personal-ap-systemd.git) git repository:

    ```
    $ cd ~
    $ git clone https://github.com/mwestphall/personal-ap-systemd.git
    ```

## Install HTCondor

1. Unpack the downloaded tarball file:

    ```
    $ tar -xf condor.tar.gz
    $ mv condor-*stripped/ condor/
    ```

1. Configure HTCondor as a single-user AP:

    ```
    $ cd condor
    $ bin/make-ap-from-tarball
    ```

1. Update your shell environment with your AP install:

    ```
    $ . ~/condor/condor.sh
    ```

1. Update your `.bashrc` to automatically set your HTCondor environment on login:

    ```
    $ echo '. ~/condor/condor.sh' >> ~/.bashrc
    ```


## Configure HTCondor for Annex Mode

To support launching EPs for your AP via a Slurm job, you must enable the optional Annex feature in HTCondor.
Annex configuration is available from this repository at [11-ap-annex.conf](./11-ap-annex.conf)

1. Copy `11-ap-annex.conf` from the `personal-ap-systemd` repository to your AP's condor config directory:

    ```
    $ cp ~/personal-ap-systemd/11-ap-annex.conf ~/condor/local/config.d/
    ```


# Personal AP SystemD Configuration

To configure your Linux host to run your Personal AP on startup, configure an unprivileged SystemD
service in your home directory.

## Configure an HTCondor service via Systemctl

1. Create a SystemD config directory in your home directory:

    ```
    $ cd ~
    $ mkdir -p ~/.config/systemd/user
    ```

1. Copy the SystemD service for htcondor from the `personal-ap-systemd` repository to your local SystemD config directory:

    ```
    $ cp ~/personal-ap-systemd/htcondor.service ~/.config/systemd/user
    ```

1. Enable the htcondor systemd service so that it begins automatically on user login.

    ```
    $ systemctl --user enable htcondor.service
    ```


## Confirm that your AP starts via Systemctl

1. Start your AP service via systemctl:

    ```
    $ systemctl start htcondor.service
    ```

1. Confirm that the systemctl service starts successfully:

    ```
    $ systemctl status --user htcondor.service
    ● htcondor.service - My user service
        Loaded: loaded (/home/westphall/.config/systemd/user/htcondor.service; enabled; preset: disabled)
        Active: active (running) since Fri 2026-08-28 13:29:21 CDT; 38min ago
    ...
    ```

## Persist the HCondor service through logouts via `loginctl`

**Note**: Depending on your system configuration, you may need to ask a system administrator to run the following command.

By default, user SystemD services exit upon user logout. To ensure that your AP continues running while you are not connected
to your linux host, set `linger` for your user via loginctl:

1. Set `enable-linger` via loginctl:

    ```
    $ loginctl enable-linger $USER
    ```

1. Confirm that lingering has been enabled for your user:

    ```
    $ loginctl show-user $USER | grep Linger
    Linger=yes
    ```


# Confirm that HTCondor Installed Properly

Before launching your first job, confirm that:

1. Your configured Systemctl service launches htcondor running as an AP.

1. Your Systemctl service perisists your AP through login sessions.

## Confirm that HTCondor is running as an AP

1. Confirm that your AP's Schedd is running.
    ```
    $ condor_q

    -- Schedd: your-ap.institution.edu : <192.168.0.1:9618?... @ 08/28/26 14:11:15
    OWNER BATCH_NAME      SUBMITTED   DONE   RUN    IDLE   HOLD  TOTAL JOB_IDS
    
    Total for query: 0 jobs; 0 completed, 0 removed, 0 idle, 0 running, 0 held, 0 suspended 
    Total for all users: 0 jobs; 0 completed, 0 removed, 0 idle, 0 running, 0 held, 0 suspended
    ```

1. Confirm that your AP's annex collector is running.
    ```
    $ condor_status -pool localhost:9618?sock=ap_collector -any
    MyType             TargetType         Name                                     
    
    Collector          None               My Pool - your-ap.institution.edu@your-ap.institution.edu
    Scheduler          None               your-ap.institution.edu
    Submitter          None               you@your-ap.institution.edu
    ```

## Confirm that Systemctl persists HTCondor processes through logouts

1. Exit all of your linux host's login sessions.

    ```
    $ logout
    ```

1. Log back onto your linux host. Confirm that your systemctl service remained active.

    ```
    $ systemctl status --user htcondor.service
    ● htcondor.service - My user service
        Loaded: loaded (/home/westphall/.config/systemd/user/htcondor.service; enabled; preset: disabled)
        Active: active (running) since Fri 2026-08-28 13:29:21 CDT; 52min ago
    ...
    ```

    Check the `Active: since <X> ago` field of the status output to confirm that the service did not restart upon login.


# Run your first HTCondor Job via an Annex with OpenOnDemand

Your Access Point (AP) configured in the previous section manages your HTCondor job queue. Additional resources are
required to to run jobs placed into that queue. An Execution Point (EP) launched via the Annex feature runs multiple 
HTCondor jobs within the lifecycle of a single Slurm job.

## Create a "Hello World" Job on your AP

Create a simple "Hello World" job on your AP, consisting of a Submit File (`hello.sub`) and an
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

# Submit your Job to run on an Annex

## Submit a Job to your AP

1. Before creating an execution point for your AP, submit a test job and label it to run on an annex via `--annex-name`:

    ```
    $ htcondor job submit hello.sub --annex-name <annex name>
    ```

    `<annex name>` should be a unique string describing the purpose of your annex.

## Create Annex Configuration

1. Create an annex tarball via `htcondor annex create`. This tarball contains a set of bash scripts that launch an EP from
   within a Slurm job.

    ```
    $ htcondor annex create --name test-annex
    
    Please copy the file annex-test-annex.tar to the HPC system
    ```

1. Copy the created tarball to your HPC login node:

    ```
    $ scp annex-test-annex.tar hpc-login.institution.edu:
    ```

## Submit your Annex via OpenOnDemand

1. Log onto your HPC cluster's OpenOnDemand Instance.

1. In the Job Composer, create a New Template for launching annex jobs.

1. Update main_job.sh in the template to the contents of [annex_submit.sh](./annex_submit.sh). 
   Set the `#SBATCH` parameters as necessary:

    ```
    #!/bin/bash
    #SBATCH --job-name=htc-annex
    #SBATCH --partition=<part>       # Partition to which you have job access
    #SBATCH --time=4:00:00           # wall time, HH:MM:SS. Adjust based on your jobs' expected runtime.
    #SBATCH --cpus-per-task=2        # Adjust based on your jobs' resource requirements.
    #SBATCH --mem=4G                 # Adjust based on your jobs' resource requirements.
    #SBATCH --output=htc-annex-app.debug
    #SBATCH --error=htc-annex-app.debug
    
    SOURCE="$HOME/annex-test-annex.tar"   # Adjust if you used a different <annex name

    ...
    ```

1. Submit a new job from this template.

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

2. Check the output of your job after it finishes:
    ```
    $ cat hello.out
    Hello, World!
    I am running on hpc-worker123
    ```
