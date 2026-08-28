# Personal AP SystemD Configuration

This repository contains instructions for installing a single-user HTCondor Access Point in unprivileged mode,
configuring the AP to run persistently via unprivileged SystemD, and creating personal Execution Points for
your AP via a Slurm Annex.

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

### Download HTCondor

HTCondor is available for download via `get.htcondor.org`:

```
$ cd ~
$ curl -fsSL https://get.htcondor.org | /bin/bash -s -- -download
```

This will download the latest release of HTCondor as a tarball file `condor.tar.gz` in your home directory.

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
