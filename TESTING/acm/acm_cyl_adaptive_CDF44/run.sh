#!/bin/bash
#-------------------------------------------------------------------------------
# WABBIT unit test
# This file contains one specific unit test, and it is called by unittest.sh
#-------------------------------------------------------------------------------
# what parameter file
dir="./TESTING/acm/acm_cyl_adaptive_CDF44/"
params=${dir}"PARAMS_cyl.ini"
happy=0
sad=0

# list of prefixes the test generates
prefixes=(ux uy p mask)
# list of possible times
times=(000000000000 000000025000 000000050000 000000075000 000000100000)


# run actual test
${mpi_command} ./wabbit ${params} ${memory}

echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo "============================"
echo "run done, analyzing results now"
echo "============================"
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""

# loop over all HDF5 files and generate keyvalues using wabbit
for p in ${prefixes[@]}
do
    for t in ${times[@]}
    do
        # *.h5 file coming out of the code...
        file=${p}"_"${t}".h5"

        # ...which we will compare to this *.h5 file
        reffile=${dir}${p}"_"${t}".h5"

        wabbit-compare-hdffiles.py ${reffile} ${file}
        result="$?"

        if [ $result == "0" ]; then
            echo -e " :) Happy, this looks ok!" $keyfile $reffile
            happy=$((happy+1))
        else
            echo -e ":[ Sad, this test failed!" $keyfile $reffile
            sad=$((sad+1))
        fi
        echo " "
        echo " "
    done
done


echo -e "\t  happy tests: \t" $happy
echo -e "\t  sad tests: \t" $sad

#-------------------------------------------------------------------------------
#                               RETURN
#-------------------------------------------------------------------------------
if [ $sad == 0 ]; then
    exit 0
else
    exit 999
fi
