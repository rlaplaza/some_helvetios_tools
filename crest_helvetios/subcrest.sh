#!/bin/bash

# We assume running this from the script directory
# Run as ./subcrest.sh myinput.xyz 
# Will submit two jobs by default, where the first one is conformational exploration with crest
# and the second one relies on the kmca.py code by R.Laplaza which should be in this directory
# The second job will be submitted with a dependency to the first job
# and will run after the crest job finishes (if it finishes) properly.

# To run only the second job, include kmca after the xyz file, like
# ./subcrest.sh myinput.xyz kmca
# And have fun. To change kmca parameters, edit the kmca.py executable. To change crest parameters
# edit the command line call in this file.

export PATH=/work/scitas-share/ddossant/xtb/6.4.1/intel-19.0.5/bin:$PATH
function is_bin_in_path {
     builtin type -P "$1" &> /dev/null
}

function qsbatch {
    sbr="$(sbatch "$@")"
    if [[ "$sbr" =~ Submitted\ batch\ job\ ([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        exit 0
    else
        echo "sbatch failed"
        exit 1
    fi
}

is_bin_in_path xtb  && echo "Found xtb." || echo "No xtb found. Exit!" 
is_bin_in_path crest  && echo "Found crest." || echo "No crest found. Exit!" 
job_directory=$(pwd)
input=${1}
pname="${1%%.xyz}"
name="${pname##*/}"
inpname="${name}.xyz"
mkdir -p ${job_directory}/info_${name}/${name}_crest
mkdir -p ${job_directory}/conformers_${name}
output="${job_directory}/info_${name}/${name}.log"
soutput="${job_directory}/info_${name}/${name}.out"
koutput="${job_directory}/info_${name}/${name}_kmca.out"
loutput="${name}.out"
natoms=$(head -n 1 ${1})
tmpdir='$SCRATCH'
curdir='$SLURM_SUBMIT_DIR'
checker='$?'

echo "Ready to create jobfile ${name}.job towards ${soutput}"
if [ -f ${job_directory}/${pname}.info ]; then
   echo "Constraint file found!"
   cp ${job_directory}/${pname}.info .xcontrol.sample
else 
   echo " " > .xcontrol.sample
fi


echo "#!/bin/bash
#SBATCH -J ${name}
#SBATCH -o ${soutput}
#SBATCH --mem=38000
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=36
#SBATCH --time=3-00:00:00
module load intel intel-mkl
ulimit -s unlimited
export OMP_STACKSIZE=4G
export OMP_MAX_ACTIVE_LEVELS=1
export OMP_NUM_THREADS=6,1
export MKL_NUM_THREADS=6
cd ${tmpdir}
cp ${curdir}/${inpname} ${tmpdir}
cp ${curdir}/.xcontrol.sample ${tmpdir}/.xcontrol.sample

crest ${name}.xyz --gfn2 --mdlen x1 --cbonds --tnmd 298.15 --rthr 0.125 --ethr 0.05  --ewin 30.0 --cinp .xcontrol.sample -T 6  -dry > ${loutput}
if [ ${checker} -eq 0 ]; then
   echo "Crest dry run seems to have terminated normally."
else 
   echo "Dry run terminated abnormally. Check crest input line."
fi

crest ${name}.xyz --gfn2 --mdlen x1 --cbonds --tnmd 298.15 --rthr 0.125 --ethr 0.05  --ewin 30.0 --cinp .xcontrol.sample -T 6  > ${loutput}
if [ ${checker} -eq 0 ]; then
   echo "Crest seems to have terminated normally."
else 
   echo "Crest terminated abnormally. Check crest input line or setup."
fi

mkdir -p ${curdir}/info_${name}/${name}_crest/
cp * ${curdir}/info_${name}/${name}_crest/
if [ ${checker} -eq 0 ]; then
   find . ! -name '*' -type f -exec rm -f {} +
   rm -rf ${tmpdir}
fi
cd ${curdir}/info_${name}/${name}_crest/ 
cp crest_conformers.xyz ${curdir}/conformers_${name}/${name}_conformers.xyz
mv ${loutput} ${output}
exit " > ${name}.job

if [ -z ${2+x} ]
then
   jid=$(qsbatch ${name}.job)
   echo "#!/bin/bash
   #SBATCH -J kmca_${name}
   #SBATCH -o ${koutput}
   #SBATCH -e ${koutput}
   #SBATCH --mem=8000
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=8
   #SBATCH --time=3-00:00:00
   ./kmca.py ${curdir}/conformers_${name}/${name}_conformers.xyz >> ${koutput}
   " > kmca_${name}.job
   sbatch --dependency=afterok:${jid} kmca_${name}.job
elif [ ${2} == "kmca" ]
then
   echo "Not doing crest. Executing kmca!"
   echo "#!/bin/bash
   #SBATCH -J kmca_${name}
   #SBATCH -o ${koutput}
   #SBATCH -e ${koutput}
   #SBATCH --mem=8000
   #SBATCH --ntasks=1
   #SBATCH --cpus-per-task=8
   #SBATCH --time=3-00:00:00
   ./kmca.py ${curdir}/conformers_${name}/${name}_conformers.xyz >> ${koutput} 
   " > kmca_${name}.job
   sbatch kmca_${name}.job
fi


