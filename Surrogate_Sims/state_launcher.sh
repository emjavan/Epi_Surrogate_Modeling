#!/bin/bash

#SBATCH -J InitInfSweep                  # Job name
#SBATCH -o InitInfSweep.%j.o             # Name of stdout output file (%j expands to jobId)
#SBATCH -e InitInfSweep.%j.e             # Name of stderr output file (%j expands to jobId)
#SBATCH -p normal                        # Queue name
#SBATCH -N 2                  	         # Total number of nodes requested
#SBATCH -n 64                            # Total number of tasks, 32 cores per node LS6
#SBATCH -t 24:00:00            	         # Run time (hh:mm:ss)
#SBATCH -A XXXXXXXX                      # Allocation name
#SBATCH --mail-user=emjavan@utexas.edu   # Email for notifications
#SBATCH --mail-type=all                  # Type of notifications, begin, end, fail, all


# Load launcher
module load launcher

# Configure launcher
EXECUTABLE=$TACC_LAUNCHER_DIR/init_launcher
PRUN=$TACC_LAUNCHER_DIR/paramrun
CONTROL_FILE=state_commands.txt
export LAUNCHER_JOB_FILE=state_commands.txt
export LAUNCHER_WORKDIR=`pwd`
export LAUNCHER_SCHED=interleaved

# Start launcher
$PRUN $EXECUTABLE $CONTROL_FILE
