Create an Open OnDemand interactive app (https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive.html)
providing a thin wrapper around the existing slurm scripts in the `ap/` directory. In the submission form, provide:
- generic config knobs (partition, cpus, memory, time limit)
- A base directory, defaulting to /scratch/$USER.

Mirror ap/ap.sub: if `<base dir>/current-ap` exists, run just start.sh against it to resume that AP, otherwise run install.sh and then start.sh.
