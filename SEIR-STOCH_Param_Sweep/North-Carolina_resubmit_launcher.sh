#!/bin/bash

#SBATCH -J North-Carolina_resub          # Job name
#SBATCH -o North-Carolina_resub.%j.o     # Name of stdout output file (%j expands to jobId)
#SBATCH -e North-Carolina_resub.%j.e     # Name of stderr output file (%j expands to jobId)
#SBATCH -p normal                        # Queue name
#SBATCH -N 8                  	         # Total number of nodes requested
#SBATCH -n 256                           # Total number of tasks, 32 cores per node LS6
#SBATCH -t 48:00:00            	         # Run time (hh:mm:ss)
#SBATCH -A TACC-SCI                      # Allocation name
#SBATCH --mail-user=emjavan@utexas.edu   # Email for notifications
#SBATCH --mail-type=all                  # Type of notifications, begin, end, fail, all

# Only 195 of 1240 scenarios began, at least 64 complete in 48hrs on 2 nodes, 64 tasks

# Load launcher
module load launcher

# Configure launcher
EXECUTABLE=$TACC_LAUNCHER_DIR/init_launcher
PRUN=$TACC_LAUNCHER_DIR/paramrun
CONTROL_FILE=North-Carolina_resubmit_commands.txt
export LAUNCHER_JOB_FILE=North-Carolina_resubmit_commands.txt
export LAUNCHER_WORKDIR=`pwd`
export LAUNCHER_SCHED=interleaved

# Start launcher
$PRUN $EXECUTABLE $CONTROL_FILE
