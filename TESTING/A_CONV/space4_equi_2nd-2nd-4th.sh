#!/bin/bash

ini=blob-convection.ini
dx=(2 3 4 5)
test_number=4
test_name="equi_2nd-2nd-4th"

# delete all data:
rm -rf dx${test_number}_*
# run tests
for ddx in ${dx[@]}
do
	dir=dx${test_number}_${test_name}_${ddx}
	mkdir $dir
	cd $dir
	cp ../$ini .
	ln -s ../../wabbit

	# time
	./replace_ini_value.sh $ini time_max 1.0
	./replace_ini_value.sh $ini dt_fixed 0.0
	./replace_ini_value.sh $ini dt_max 2.0e-3
	./replace_ini_value.sh $ini CFL 1.2

	# order
	./replace_ini_value.sh $ini order_discretization FD_2nd_central
	./replace_ini_value.sh $ini order_predictor multiresolution_2nd

	# blocks
	./replace_ini_value.sh $ini adapt_mesh 0 
	./replace_ini_value.sh $ini adapt_inicond 0
	./replace_ini_value.sh $ini inicond_refinements 0
	./replace_ini_value.sh $ini number_block_nodes 17
	./replace_ini_value.sh $ini number_ghost_nodes 4
	./replace_ini_value.sh $ini eps 1.0e-3
	./replace_ini_value.sh $ini max_treelevel $ddx
	./replace_ini_value.sh $ini min_treelevel $ddx

	# other
	./replace_ini_value.sh $ini nu 0.0
	./replace_ini_value.sh $ini blob_width 0.01
	
	$mpi ./wabbit 2D $ini --memory=0.5GB
	cd ..
done