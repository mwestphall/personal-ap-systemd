Create an Open OnDemand interactive app (https://osc.github.io/ood-documentation/latest/how-tos/app-development/interactive.html)
providing a thin wrapper around the existing slurm scripts in the `ap/` directory. In the submission form, provide:
- generic config knobs (partition, cpus, memory, time limit)
- An "working directory", left blank by default.

If the working directory is left blank, run both install.sh and start.sh, otherwise just start.sh against the existing directory.
Fail fast if the user attempts to point at an invalid existing directory.
