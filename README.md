# Personal HTCondor Cluster on CHTC Open OnDemand

This repository contains instructions for launching a single-user HTCondor cluster on CHTC's [Open OnDemand instance](https://ondemand.chtc.wisc.edu/):
- Creating an HTCondor Submit Node (Access Point) for managing your HTCondor jobs via a long-lived Slurm job.
- Creating Execution Points (EPs) for running your HTCondor jobs, also via Slurm jobs.
- Submitting HTCondor jobs using Open OnDemand's interactive web terminal.

# Log into CHTC's Open OnDemand

CHTC's Open OnDemand instance can be accessed at [ondemand.chtc.wisc.edu](https://ondemand.chtc.wisc.edu/). Log in using your UW NetID and Password.

If you are unable to access the cluster, [apply for access](https://chtc.wisc.edu/uw-research-computing/form.html) via the CHTC user app.

# Schedule an Access Point on your Slurm Cluster

Your Personal AP manages the state of your HTCondor job queue.

The **Personal HTCondor AP** interactive app launches a Slurm job that:

1. Downloads (if needed) the HTCondor binaries.

1. Configures HTCondor to run as an Access Point in single-user mode under your Unix account.

1. Creates configuration that points HTCondor command line tools at your running AP.

To launch an instance of the Personal HTCondor AP interactive app:

1. Navigate to the "Interactive Apps" section of the Open OnDemand dashboard.

   ![Interactive App Dropdown](/docs/interactive-apps.png)

1. Select "Personal HTCondor AP".

1. In the app's submission form, select a slurm partition and resource requests for your AP.
    - All fields may be left as the default.

1. "Launch" the app.

1. Watch the status of your AP interactive app. Wait for the AP app to reach the "Running" state. 

   ![AP Status](/docs/ap-status.png)

# Schedule an Execution Point on your Slurm Cluster

Additional resources are required to to run jobs placed into your AP's queue. 
An Execution Point (EP) runs multiple HTCondor jobs within the lifecycle 
of a single Slurm job.

## Schedule an Execution Point

The **Personal HTCondor EP** interactive app launches a Slurm script that auto-configures an EP to run the jobs scheduled in your AP.

To launch an instance of the Personal HTCondor EP app:

1. Navigate to the "Interactive Apps" section of the Open OnDemand dashboard.

1. Select "Personal HTCondor EP".

1. In the app's submission form, select a slurm partition and resource requests for your EP.
    - All fields may be left as the default.

1. "Launch" the app.

1. Watch the status of your AP interactive app. Wait for the EP app to reach the "Running" state, and for the AP app to detect the running EP. 

   ![AP Status with EP](/docs/ap-status-with-ep.png)

# Submit your first HTCondor Job to your AP

Your Access Point (AP) configured in the previous section manages your HTCondor job queue, while the
Execution Point (EP) runs any submitted workloads.

Place a "Hello World" HTCondor job into your AP's job queue.


1. Access the Spark Login Node

    Open a Shell on the Spark login node via the "CHTC Spark Cluster Shell Access" menu item in Open OnDemand.
    You will be prompted to log in again with your NetID and password.

1. Set up your HTCondor environment

    Source the following file in your home directory:

    ```
    $ . ~/.cache/current-ap/condor.sh
    ```

    You may also add the above line to your `~/.bashrc` to perform this configuration on every login.

1. Create a "Hello World" Job

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

1. Submit your HTCondor Job to your AP

    ```
    $ condor_submit hello.sub
    ```

1. Confirm that your Job Runs on the EP

    ```
    $ condor_watch_q
    ```

1. Check the output of your job after it finishes

    ```
    $ cat hello.out
    Hello, World!
    I am running on hpc-worker123
    ```

# Additional Utilities

## Resume an Access Point

The AP configured by the **Personal HTCondor AP** app will exit after 4 hours by default. To resume your AP after it exits,
re-run the Personal AP interactive app, ensuring that the "Resume AP" checkbox is checked.

To launch a fresh AP, discarding your previous instance, re-run the app with the "Resume AP" checkbox unchecked.


## Add Execution Points

To run larger workloads on your HTCondor cluster, you can schedule additional EPs onto your Slurm workers by re-running the **Personal HTCondor EP** interactive app.

Each instance of the EP app will provide additional compute capacity to your cluster.
