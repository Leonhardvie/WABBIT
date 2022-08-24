!! \author  engels
!
!> \brief This routine performs the coarsing of the mesh, where possible. For the given mesh
!! we compute the details-coefficients on all blocks. If four sister blocks have maximum
!! details below the specified tolerance, (so they are insignificant), they are merged to
!! one coarser block one level below. This process is repeated until the grid does not change
!! anymore.
!!
!! As the grid changes, active lists and neighbor relations are updated, and load balancing
!! is applied.
!
!> \note The block thresholding is done with the restriction/prediction operators acting on the
!! entire block, INCLUDING GHOST NODES. Ghost node syncing is performed in threshold_block.
!
!> \note It is well possible to start with a very fine mesh and end up with only one active
!! block after this routine. You do *NOT* have to call it several times.
subroutine adapt_tree( time, params, hvy_block, tree_ID, indicator, hvy_tmp, hvy_mask, external_loop, ignore_maxlevel)

    implicit none

    real(kind=rk), intent(in)           :: time
    !> user defined parameter structure
    type (type_params), intent(in)      :: params
    !> heavy data array
    real(kind=rk), intent(inout)        :: hvy_block(:, :, :, :, :)
    !> heavy work data array - block data.
    real(kind=rk), intent(inout)        :: hvy_tmp(:, :, :, :, :)
    ! mask data. we can use different trees (4est module) to generate time-dependent/indenpedent
    ! mask functions separately. This makes the mask routines tree-level routines (and no longer
    ! block level) so the physics modules have to provide an interface to create the mask at a tree
    ! level. All parts of the mask shall be included: chi, boundary values, sponges.
    ! Optional: if the grid is not adapted to the mask, passing hvy_mask is not required.
    real(kind=rk), intent(inout), optional :: hvy_mask(:, :, :, :, :)
    character(len=*), intent(in)        :: indicator
    !> Well, what now. The grid coarsening is an iterative process that runs until no more blocks can be
    !! coarsened. One iteration is not enough. If called without "external_loop", this routine
    !! performs this loop until it is converged. In some situations, this might be undesired, and
    !! the loop needs to be outsourced to the calling routine. This happens currently (07/2019)
    !! only in the initial condition, where the first grid can be so coarse that the inicond is different
    !! only on one point, which is then completely removed (happens for a mask function, for example.)
    !! if external_loop=.true., only one iteration step is performed.
    logical, intent(in), optional       :: external_loop
    ! during mask generation it can be required to ignore the maxlevel coarsening....life can suck, at times.
    logical, intent(in), optional       :: ignore_maxlevel

    integer(kind=ik), intent(in)        :: tree_ID
    ! loop variables
    integer(kind=ik)                    :: lgt_n_old, iteration, k, lgt_id
    real(kind=rk)                       :: t0, t1
    integer(kind=ik)                    :: ierr, k1, hvy_id
    logical                             :: ignore_maxlevel2, iterate
    ! level iterator loops from Jmax_active to Jmin_active for the levelwise coarsening
    integer(kind=ik)                    :: Jmax_active, Jmin_active, level, Jmin

    ! NOTE: after 24/08/2022, the arrays lgt_active/lgt_n hvy_active/hvy_n as well as lgt_sortednumlist,
    ! hvy_neighbors, tree_N and lgt_block are global variables included via the module_forestMetaData. This is not
    ! the ideal solution, as it is trickier to see what does in/out of a routine. But it drastically shortenes
    ! the subroutine calls, and it is easier to include new variables (without having to pass them through from main
    ! to the last subroutine.)  -Thomas


    ! start time
    t0 = MPI_Wtime()
    t1 = t0
    lgt_n_old = 0
    iteration = 0
    iterate   = .true.
    Jmin      = params%min_treelevel
    Jmin_active = minActiveLevel_tree(tree_ID)
    Jmax_active = maxActiveLevel_tree(tree_ID)
    level       = Jmax_active ! algorithm starts on maximum *active* level

    if (present(ignore_maxlevel)) then
        ignore_maxlevel2 = ignore_maxlevel
    else
        ignore_maxlevel2 = .false.
    endif


    ! To avoid that the incoming hvy_neighbor array and active lists are outdated
    ! we synchronize them.
    t0 = MPI_Wtime()
    call updateMetadata_tree(params, tree_ID)
    call toc( "adapt_tree (update neighbors)", MPI_Wtime()-t0 )

    !! we iterate from the highest current level to the lowest current level and then iterate further
    !! until the number of blocks is constant (note: as only coarsening
    !! is done here, no new blocks arise that could compromise the number of blocks -
    !! if it's constant, its because no more blocks are coarsened)
    do while (iterate)
        lgt_n_old = lgt_n(tree_ID)

        !> (a) check where coarsening is possible
        ! ------------------------------------------------------------------------------------
        ! first: synchronize ghost nodes - thresholding on block with ghost nodes
        ! synchronize ghostnodes, grid has changed, not in the first one, but in later loops
        t0 = MPI_Wtime()
        call sync_ghosts( params, lgt_block, hvy_block, hvy_neighbor, hvy_active(:, tree_ID), hvy_n(tree_ID) )
        call toc( "adapt_tree (sync_ghosts)", MPI_Wtime()-t0 )

        !! calculate detail on the entire grid. Note this is a wrapper for coarseningIndicator_block, which
        !! acts on a single block only
        t0 = MPI_Wtime()
        if (params%threshold_mask .and. present(hvy_mask)) then
            ! if present, the mask can also be used for thresholding (and not only the state vector). However,
            ! as the grid changes within this routine, the mask will have to be constructed in coarseningIndicator_tree
            call coarseningIndicator_tree( time, params, level, hvy_block, hvy_tmp, tree_ID, indicator, iteration, ignore_maxlevel2, hvy_mask)
        else
            call coarseningIndicator_tree( time, params, level, hvy_block, hvy_tmp, tree_ID, indicator, iteration, ignore_maxlevel2)
        endif
        call toc( "adapt_tree (coarseningIndicator_tree)", MPI_Wtime()-t0 )


        !> (b) check if block has reached maximal level, if so, remove refinement flags
        t0 = MPI_Wtime()
        if (ignore_maxlevel2 .eqv. .false.) then
            call respectJmaxJmin_tree( params, tree_ID )
        endif
        call toc( "adapt_tree (respectJmaxJmin_tree)", MPI_Wtime()-t0 )

        !> (c) unmark blocks that cannot be coarsened due to gradedness and completeness
        t0 = MPI_Wtime()
        call ensureGradedness_tree( params, tree_ID )
        call toc( "adapt_tree (ensureGradedness_tree)", MPI_Wtime()-t0 )

        !> (d) adapt the mesh, i.e. actually merge blocks
        t0 = MPI_Wtime()
        if (params%threshold_mask .and. present(hvy_mask)) then
            ! if the mask function is used as secondary coarsening criterion, we also pass the mask data array.
            ! the idea is that now coarse-mesh will keep both hvy_block and hvy_mask on the same grid, i.e.
            ! the same coarsening is applied to both. the mask does not have to be re-created here, because
            ! regions with sharp gradients (that's where the mask is interesting) will remain unchanged
            ! by the coarsening function.
            ! This is not entirely true: often, adapt_tree is called after refine_tree, which pushes the grid
            ! to Jmax. If the dealiasing function is on (params%force_maxlevel_dealiasing=.true.), the coarsening
            ! has to go down one level. If the mask is on Jmax on input and yet still poorly resolved (say, only one point nonzero)
            ! then it can happen that the mask is gone after executeCoarsening_tree.
            ! There is some overhead involved with keeping both structures the same, in the sense
            ! that MPI-communication is increased, if blocks on different CPU have to merged.
            call executeCoarsening_tree( params, hvy_block, tree_ID, hvy_mask )
        else

            call executeCoarsening_tree( params, hvy_block, tree_ID )
        endif
        call toc( "adapt_tree (executeCoarsening_tree)", MPI_Wtime()-t0 )


        ! update grid lists: active list, neighbor relations, etc
        t0 = MPI_Wtime()
        call updateMetadata_tree(params, tree_ID)
        call toc( "adapt_tree (update neighbors)", MPI_Wtime()-t0 )


        ! see description above in argument list.
        if (present(external_loop)) then
            if (external_loop) exit ! exit loop
        endif

        iteration = iteration + 1
        level = level - 1

        ! loop condition for outer iteration depends on the transform type:
        ! for biorthogonal, we have to consider all levels individidually (Note: it may well
        ! be that on some level, nothing can be coarsened, but on the levels below, it is possible.
        ! Hence checking for a constant grid is misleading at this time.)
        ! for harten-multiresolution, its sufficient to iterate until the grid is constant
        if (params%wavelet_transform_type=="biorthogonal") then
            iterate = (level >= Jmin)
        else
            iterate = (lgt_n_old /= lgt_n(tree_ID))
        endif
    end do

    ! The grid adaptation is done now, the blocks that can be coarsened are coarser.
    ! If a block is on Jmax now, we assign it the status +11.
    !
    ! NOTE: Consider two blocks, a coarse on Jmax-1 and a fine on Jmax. If you refine only
    ! the coarse one (Jmax-1 -> Jmax), because you cannot refine the other one anymore
    ! (by defintion of Jmax), then the redundant layer in both blocks is different.
    ! To corrent that, you need to know which of the blocks results from interpolation and
    ! which one has previously been at Jmax. This latter one gets the 11 status.
    !
    ! NOTE: If the flag ghost_nodes_redundant_point_coarseWins is true, then the +11 status is useless
    ! because the redundant points are overwritten on the fine block with the coarser values
    if ( .not. params%ghost_nodes_redundant_point_coarseWins ) then
        do k = 1, lgt_n(tree_ID)
            lgt_id = lgt_active(k, tree_ID)
            if ( lgt_block( lgt_id, params%max_treelevel+ IDX_MESH_LVL) == params%max_treelevel ) then
                lgt_block( lgt_id, params%max_treelevel + IDX_REFINE_STS ) = 11
            end if
        end do
    end if

    !> At this point the coarsening is done. All blocks that can be coarsened are coarsened
    !! they may have passed several level also. Now, the distribution of blocks may no longer
    !! be balanced, so we have to balance load now
    t0 = MPI_Wtime()
    call balanceLoad_tree( params, hvy_block, tree_ID )
    call toc( "adapt_tree (balanceLoad_tree)", MPI_Wtime()-t0 )


    call toc( "adapt_tree (TOTAL)", MPI_wtime()-t1)
end subroutine adapt_tree
