module module_MPI

    use mpi
    use module_params
    use module_timing
    use module_wavelets
    use module_treelib
    use module_helpers

    implicit none

    ! I usually find it helpful to use the private keyword by itself initially, which specifies
    ! that everything within the module is private unless explicitly marked public.
    PRIVATE

    ! everything is save by default
    SAVE

    ! send/receive buffer, integer and real
    ! allocate in init substep not in synchronize subroutine, to avoid slow down when using
    ! large numbers of processes and blocks per process, when allocating on every call to the routine
    integer(kind=ik), allocatable :: iMetaData_sendBuffer(:), iMetaData_recvBuffer(:)
    integer(kind=ik), allocatable :: MetaData_recvCounter(:), MetaData_sendCounter(:)
    integer(kind=ik), allocatable :: Data_recvCounter(:), Data_sendCounter(:)
    integer(kind=ik), allocatable :: real_pos(:), internalNeighborSyncs(:)
    real(kind=rk), allocatable    :: rData_sendBuffer(:), rData_recvBuffer(:)
    integer(kind=ik) :: internalNeighbor_pos
    !
    integer(kind=ik), allocatable :: send_request(:)
    integer(kind=ik), allocatable :: recv_request(:)

    ! an array to count how many messages we send to the other mpiranks.
    integer(kind=ik), allocatable :: int_pos(:)

    ! internally, we flatten the ghost nodes layers to a line. this is stored in
    ! this buffer (NOTE max size is (blocksize)*(ghost nodes size + 1)*(number of datafields))
    real(kind=rk), allocatable    :: line_buffer(:)

    ! restricted/predicted data buffer
    real(kind=rk), allocatable    :: res_pre_data(:,:,:,:), tmp_block(:,:,:,:)

    ! it is faster to use named consts than strings, although strings are nicer to read
    integer(kind=ik), PARAMETER   :: SENDER = 1, RECVER = 2, RESPRE = 3

    ! we set up a table that gives us directly the inverse neighbor relations.
    ! it is filled (once) in init_ghost_nodes
    integer(kind=ik), dimension(1:74,2:3) :: inverse_neighbor

    ! We frequently need to know the indices of a ghost nodes chunk. Thus we save them
    ! once in a large, module-global array (which is faster than computing it every time with tons
    ! of IF-THEN clauses).
    ! This arrays indices are:
    ! ijkGhosts([start,end], [dir (x,y,z)], [neighborhood], [level-diff], [sender/receiver/up-downsampled])
    integer(kind=ik), dimension(1:2, 1:3, 1:74, -1:1, 1:3) :: ijkGhosts

    ! it is useful to keep a named constant for the dimensionality here (we use
    ! it to access e.g. two/three D arrays in inverse_neighbor)
    integer(kind=ik) :: dim

    ! we use this flag to call the allocation routine only once.
    logical :: ghost_nodes_module_ready = .false.

    ! FIXME: This is a very large work array - equivalent of a whole statevector copy.
    ! only a subset of it will be actually used, still.
    ! Its tedious to pass another work array (and hvy_tmp is not the right size neither)
    ! So for now this is a HACK solution
    real(kind=rk), allocatable :: hvy_filtered(:, :, :, :, :)
    ! the 2nd one is small:
    logical, allocatable :: isFiltered(:)



    ! two shift parameters (asymmetric and symmetric ) used for selection of interpolation
    ! bounds on sender side. used to avoid one-sided interpolation if desired. They're
    ! global so we can save them easily to the ghosts_bounds.dat file
    integer(kind=ik) :: A, S

!---------------------------------------------------------------------------------------------
! public parts of this module

    PUBLIC :: sync_ghosts, blocks_per_mpirank, synchronize_lgt_data, reset_ghost_nodes
    PUBLIC :: init_ghost_nodes, coarseExtensionUpdate_tree!, sync_ghosts_nostages


contains

#include "synchronize_ghosts_generic.f90"
#include "blocks_per_mpirank.f90"
#include "synchronize_lgt_data.f90"
#include "reset_ghost_nodes.f90"
#include "calc_data_bounds.f90"
#include "restrict_predict_data.f90"
#include "reconstruction_step.f90"

!! initialize ghost nodes module. allocate buffers and create data bounds array,
!! which we use to rapidly identify a ghost nodes layer
subroutine init_ghost_nodes( params )
    implicit none
    type (type_params), intent(in) :: params
    ! local variables
    integer(kind=ik) :: buffer_N_int, buffer_N, g, Neqn, number_blocks, rank
    integer(kind=ik), dimension(3) :: Bs
    integer(kind=ik) :: ineighbor, Nneighbor, leveldiff, Ncpu
    integer(kind=ik) ::  j, rx0, rx1, ry0, ry1, rz0, rz1, sx0, sx1, sy0, sy1, sz0, sz1
    integer(kind=ik) :: i, k, status(1:4)
    integer(kind=ik) :: ijkrecv(2,3)
    integer(kind=ik) :: ijkbuffer(2,3)
    integer(kind=ik) :: ijksend(2,3)

    ! on second call, nothing happens
    if (.not. ghost_nodes_module_ready) then
        number_blocks   = params%number_blocks
        Bs              = params%Bs
        g               = params%g
        ! HACK: in the design phase, we thought to always sync neqn commponents
        ! but in some cases we end up synching more!
        Neqn            = N_MAX_COMPONENTS
        rank            = params%rank
        Ncpu            = params%number_procs

        if (rank==0) then
            write(*,'("---------------------------------------------------------")')
            write(*,'("             ╱▔▔▔▔▔▔╲ ╭━━━━━━━━━━╮")')
            write(*,'("            ▕ ╭━╮╭━╮ ▏┃GHOST-INIT┃")')
            write(*,'("            ▕ ┃╭╯╰╮┃ ▏╰┳━━━━━━━━━╯")')
            write(*,'("            ▕ ╰╯╭╮╰╯ ▏ ┃ ")')
            write(*,'("            ▕   ┃┃   ▏━╯ ")')
            write(*,'("            ▕   ╰╯   ▏" )')
            write(*,'("            ▕╱╲╱╲╱╲╱╲▏")')
            write(*,'("---------------------------------------------------------")')
            write(*,'("GHOSTS-INIT: We can synchronize at most N_MAX_COMPONENTS=",i2)') N_MAX_COMPONENTS
            write(*,'("GHOSTS-INIT: g=",i2)') params%g
        endif

        if ( params%dim==3 ) then
            if (g>=(Bs(1)+1)/2 .or. g>=(Bs(2)+1)/2 .or. g>=(Bs(3)+1)/2) then
              call abort(921151369, "Young skywalker, you failed at set g>=(Bs+1)/2 (in at least one direction) which implies &
              & that the ghost nodes layer can span beyond an entire finer block. Either decrease &
              & number_ghost_nodes or increase number_block_nodes.")
            endif
        else
            if (g>=(Bs(1)+1)/2 .or. g>=(Bs(2)+1)/2) then
              call abort(821151369, "Young skywalker, you failed at set g>=(Bs+1)/2 (in at least one direction) which implies &
              & that the ghost nodes layer can span beyond an entire finer block. Either decrease &
              & number_ghost_nodes or increase number_block_nodes.")
            endif
        endif

        ! synchronize buffer length
        ! assume: all blocks are used, all blocks have external neighbors,
        ! max number of active neighbors: 2D = 12, 3D = 56
        dim = params%dim
        if ( dim == 3 ) then
            !---3d---3d---
            ! per neighborhood relation, we send 6 integers as metadata in the int_buffer
            ! at most, we can have 56 neighbors ACTIVE per block
            buffer_N_int = number_blocks * 56 * 6
            ! how many possible neighbor relations are there?
            Nneighbor = 74
        else
            !---2d---2d---
            ! per neighborhood relation, we send 6 integers as metadata in the int_buffer
            ! at most, we can have 12 neighbors ACTIVE per block
            buffer_N_int = number_blocks * 12 * 6
            ! how many possible neighbor relations are there?
            Nneighbor = 16
        end if

        ! size of ghost nodes buffer. Note this contains only the ghost nodes layer
        ! for all my blocks
        if ( dim == 3 ) then
            buffer_N = number_blocks * Neqn * ( (Bs(1)+2*g)*(Bs(2)+2*g)*(Bs(3)+2*g) - (Bs(1)*Bs(2)*Bs(3)) )
        else
            ! 2D case
            buffer_N = number_blocks * Neqn * ( (Bs(1)+2*g)*(Bs(2)+2*g) - (Bs(1)*Bs(2)) )
        end if

        !-----------------------------------------------------------------------
        ! allocate auxiliary memory
        !-----------------------------------------------------------------------
        ! allocate synch buffer
        if (rank==0) then
            write(*,'("GHOSTS-INIT: Attempting to allocate the ghost-sync-buffer.")')

            write(*,'("GHOSTS-INIT: buffer_N_int=",i12," buffer_N=",i12)') &
            buffer_N_int, buffer_N

            write(*,'("GHOSTS-INIT: On each MPIRANK, Int  buffer:", f9.4, "GB")') &
                2.0*dble(buffer_N_int)*8e-9

            write(*,'("GHOSTS-INIT: On each MPIRANK, Real buffer:", f9.4, "GB")') &
                2.0*dble(buffer_N)*8e-9
            write(*,'("---------------- allocating now ----------------")')
        endif

        ! wait now so that if allocation fails, we get at least the above info
        call MPI_barrier( WABBIT_COMM, status(1))

        allocate( internalNeighborSyncs(1:buffer_N_int), stat=status(1) )
        allocate( iMetaData_sendBuffer(1:buffer_N_int), stat=status(1) )
        allocate( iMetaData_recvBuffer(1:buffer_N_int), stat=status(2) )
        allocate( rData_sendBuffer(1:buffer_N), stat=status(3) )
        allocate( rData_recvBuffer(1:buffer_N), stat=status(4) )

        if (maxval(status) /= 0) call abort(999999, "Buffer allocation failed. Not enough memory?")

        if (rank==0) then
            write(*,'("GHOSTS-INIT: on each mpirank, Allocated ",A25," SHAPE=",7(i9,1x))') &
            "rData_sendBuffer", shape(rData_sendBuffer)

            write(*,'("GHOSTS-INIT: on each mpirank, Allocated ",A25," SHAPE=",7(i9,1x))') &
            "rData_recvBuffer", shape(rData_recvBuffer)

            write(*,'("GHOSTS-INIT: on each mpirank, Allocated ",A25," SHAPE=",7(i9,1x))') &
            "iMetaData_sendBuffer", shape(iMetaData_sendBuffer)

            write(*,'("GHOSTS-INIT: on each mpirank, Allocated ",A25," SHAPE=",7(i9,1x))') &
            "iMetaData_recvBuffer", shape(iMetaData_recvBuffer)

            write(*,'("GHOSTS-INIT: on each mpirank, rData_sendBuffer size is",f9.4," GB ")') &
            product(real(shape(rData_sendBuffer)))*8e-9

            write(*,'("GHOSTS-INIT: on each mpirank, rData_recvBuffer size is",f9.4," GB ")') &
            product(real(shape(rData_recvBuffer)))*8e-9

            write(*,'("GHOSTS-INIT: on each mpirank, iMetaData_sendBuffer size is",f9.4," GB ")') &
            product(real(shape(iMetaData_sendBuffer)))*4e-9

            write(*,'("GHOSTS-INIT: on each mpirank, iMetaData_recvBuffer size is",f9.4," GB ")') &
            product(real(shape(iMetaData_recvBuffer)))*4e-9
        endif

        allocate( send_request(1:2*Ncpu) )
        allocate( recv_request(1:2*Ncpu) )
        allocate( int_pos(1:Ncpu) )
        allocate( real_pos(1:Ncpu) )
        allocate( line_buffer( 1:Neqn*product(Bs(1:params%dim)+2*g) ) )
        allocate( Data_recvCounter(0:Ncpu-1), Data_sendCounter(0:Ncpu-1) )
        allocate( MetaData_recvCounter(0:Ncpu-1), MetaData_sendCounter(0:Ncpu-1) )

        ! wait now so that if allocation fails, we get at least the above info
        call MPI_barrier( WABBIT_COMM, status(1))

        !-----------------------------------------------------------------------
        ! set up constant arrays
        !-----------------------------------------------------------------------
        ! We frequently need to know the indices of a ghost nodes patch. Thus we save them
        ! once in a module-global array (which is faster than computing it every time with tons
        ! of IF-THEN clauses).
        ! This arrays indices are:
        ! ijkGhosts([start,end], [dir], [ineighbor], [leveldiff], [isendrecv])
        call ghosts_setup_patches(params, gminus=params%g, gplus=params%g, output_to_file=.true.)

        ! set up table with inverse neighbor relations
        if (.true.) then ! for folding only
            inverse_neighbor = -1
            ! ---2D------2D------2D---
            inverse_neighbor(1,2) = 3
            inverse_neighbor(2,2) = 4
            inverse_neighbor(3,2) = 1
            inverse_neighbor(4,2) = 2
            inverse_neighbor(5,2) = 8
            inverse_neighbor(6,2) = 7
            inverse_neighbor(7,2) = 6
            inverse_neighbor(8,2) = 5
            inverse_neighbor(9,2) = 11
            inverse_neighbor(10,2) = 12
            inverse_neighbor(11,2) = 9
            inverse_neighbor(12,2) = 10
            inverse_neighbor(13,2) = 15
            inverse_neighbor(14,2) = 16
            inverse_neighbor(15,2) = 13
            inverse_neighbor(16,2) = 14
            ! ---3D------3D------3D------3D---
            !'__1/___', '__2/___', '__3/___', '__4/___', '__5/___', '__6/___'
            inverse_neighbor(1,3) = 6
            inverse_neighbor(2,3) = 4
            inverse_neighbor(3,3) = 5
            inverse_neighbor(4,3) = 2
            inverse_neighbor(5,3) = 3
            inverse_neighbor(6,3) = 1
            !'_12/___', '_13/___', '_14/___', '_15/___'
            inverse_neighbor(7,3) = 13
            inverse_neighbor(8,3) = 14
            inverse_neighbor(9,3) = 11
            inverse_neighbor(10,3) = 12
            !'_62/___', '_63/___', '_64/___', '_65/___'
            inverse_neighbor(11,3) = 9
            inverse_neighbor(12,3) = 10
            inverse_neighbor(13,3) = 7
            inverse_neighbor(14,3) = 8
            !'_23/___', '_25/___'
            inverse_neighbor(15,3) = 18
            inverse_neighbor(16,3) = 17
            !'_43/___', '_45/___'
            inverse_neighbor(17,3) = 16
            inverse_neighbor(18,3) = 15
            !'123/___', '134/___', '145/___', '152/___'
            inverse_neighbor(19,3) = 25
            inverse_neighbor(20,3) = 26
            inverse_neighbor(21,3) = 23
            inverse_neighbor(22,3) = 24
            !'623/___', '634/___', '645/___', '652/___'
            inverse_neighbor(23,3) = 21
            inverse_neighbor(24,3) = 22
            inverse_neighbor(25,3) = 19
            inverse_neighbor(26,3) = 20
            !'__1/123', '__1/134', '__1/145', '__1/152'
            inverse_neighbor(27,3) = 47
            inverse_neighbor(28,3) = 48
            inverse_neighbor(29,3) = 49
            inverse_neighbor(30,3) = 50
            !'__2/123', '__2/623', '__2/152', '__2/652'
            inverse_neighbor(31,3) = 39
            inverse_neighbor(32,3) = 40
            inverse_neighbor(33,3) = 41
            inverse_neighbor(34,3) = 42
            !'__3/123', '__3/623', '__3/134', '__3/634'
            inverse_neighbor(35,3) = 45
            inverse_neighbor(36,3) = 46
            inverse_neighbor(37,3) = 43
            inverse_neighbor(38,3) = 44
            !'__4/134', '__4/634', '__4/145', '__4/645'
            inverse_neighbor(39,3) = 31
            inverse_neighbor(40,3) = 32
            inverse_neighbor(41,3) = 33
            inverse_neighbor(42,3) = 34
            !'__5/145', '__5/645', '__5/152', '__5/652'
            inverse_neighbor(43,3) = 37
            inverse_neighbor(44,3) = 38
            inverse_neighbor(45,3) = 35
            inverse_neighbor(46,3) = 36
            !'__6/623', '__6/634', '__6/645', '__6/652'
            inverse_neighbor(47,3) = 27
            inverse_neighbor(48,3) = 28
            inverse_neighbor(49,3) = 29
            inverse_neighbor(50,3) = 30
            !'_12/123', '_12/152', '_13/123', '_13/134', '_14/134', '_14/145', '_15/145', '_15/152'
            inverse_neighbor(51,3) = 63
            inverse_neighbor(52,3) = 64
            inverse_neighbor(53,3) = 66!65
            inverse_neighbor(54,3) = 65!66
            inverse_neighbor(55,3) = 59
            inverse_neighbor(56,3) = 60
            inverse_neighbor(57,3) = 62
            inverse_neighbor(58,3) = 61
            !'_62/623', '_62/652', '_63/623', '_63/634', '_64/634', '_64/645', '_65/645', '_65/652'
            inverse_neighbor(59,3) = 55
            inverse_neighbor(60,3) = 56
            inverse_neighbor(61,3) = 58
            inverse_neighbor(62,3) = 57
            inverse_neighbor(63,3) = 51
            inverse_neighbor(64,3) = 52
            inverse_neighbor(65,3) = 54!53
            inverse_neighbor(66,3) = 53!54
            !'_23/123', '_23/623', '_25/152', '_25/652'
            inverse_neighbor(67,3) = 73
            inverse_neighbor(68,3) = 74
            inverse_neighbor(69,3) = 71
            inverse_neighbor(70,3) = 72
            !'_43/134', '_43/634', '_45/145', '_45/645'
            inverse_neighbor(71,3) = 69
            inverse_neighbor(72,3) = 70
            inverse_neighbor(73,3) = 67
            inverse_neighbor(74,3) = 68
        endif

        ! this routine is not performance-critical
        call MPI_barrier( WABBIT_COMM, status(1))

        if (rank==0) then
            write(*,'("---------------------------------------------------------")')
            write(*,'("                     GHOST-INIT complete :)")')
            write(*,'("---------------------------------------------------------")')
        endif

        ghost_nodes_module_ready = .true.
    endif

end subroutine

subroutine ghosts_ensure_correct_buffer_size(params, hvy_block)
    implicit none
    type (type_params), intent(in) :: params
    real(kind=rk), intent(inout)   :: hvy_block(:, :, :, :, :)

    integer(kind=ik) :: i,j,k, Bs(1:3), g, nx, ny, nz, nc

    if (allocated(res_pre_data)) deallocate(res_pre_data)
    if (allocated(tmp_block)) deallocate(tmp_block)

    Bs = params%Bs
    g  = params%g
    nx = size(hvy_block,1)
    ny = size(hvy_block,2)
    nz = size(hvy_block,3)
    nc = size(hvy_block,4)

    ! now we know how large the patches are we'd like to store in the RESPRE buffer
    i = maxval( ijkGhosts(2,1,:,:,RESPRE) )*2
    j = maxval( ijkGhosts(2,2,:,:,RESPRE) )*2
    k = maxval( ijkGhosts(2,3,:,:,RESPRE) )*2

    allocate( res_pre_data( i, j, k, nc) )

    if (params%dim == 3) then
        allocate( tmp_block( Bs(1)+2*g, Bs(2)+2*g, Bs(3)+2*g, nc) )
    else
        allocate( tmp_block( Bs(1)+2*g, Bs(2)+2*g, 1, nc) )
    endif

    if (allocated(isFiltered)) then
        if (size(isFiltered,1)<size(hvy_block,5)) deallocate(isFiltered)
    endif
    if (.not. allocated(isFiltered)) allocate(isFiltered(1:size(hvy_block,5)))
    ! this one needs initializing:
    isFiltered = .false.

    if (allocated(hvy_filtered)) then
        if (.not. areArraysSameSize(hvy_block, hvy_filtered)) deallocate(hvy_filtered)
    endif
    ! FIXME: This is a very large work array - equivalent of a whole statevector copy.
    ! only a subset of it will be actually used, still
    if (.not. allocated(hvy_filtered)) allocate(hvy_filtered(1:nx, 1:ny, 1:nz, 1:nc, 1:size(hvy_block,5)) )


end subroutine


! setup the ghost patches (i.e. the indices of the sender/receiver parts
! for any neighborhood relation), where a smaller subset of the ghost nodes
! can be synced (the g you pass must be <= params%g)
subroutine ghosts_setup_patches(params, gminus, gplus, output_to_file)
    implicit none
    type (type_params), intent(in) :: params
    integer(kind=ik), intent(in) :: gminus, gplus
    logical, intent(in) :: output_to_file

    integer(kind=ik) :: N_neighbors, level_diff, neighborhood, i, j, k
    integer(kind=ik) :: ijkrecv(2,3)
    integer(kind=ik) :: ijkbuffer(2,3)
    integer(kind=ik) :: ijksend(2,3)

    ! full reset of all patch definitions. Note we set 1 not 0
    ijkGhosts = 1

    N_neighbors = 74
    if (params%dim==2) N_neighbors=16

    do neighborhood = 1, N_neighbors
        do level_diff = -1, 1
            !---------larger ghost nodes (used for refinement and coarsening and maybe RHS)------------
            ! The receiver bounds are hard-coded with a huge amount of tedious indices.
            call set_recv_bounds( params, ijkrecv, neighborhood, level_diff, gminus, gplus)
            ijkGhosts(1:2, 1:3, neighborhood, level_diff, RECVER) = ijkrecv

            ! Luckily, knowing the receiver bounds, we can compute the sender bounds as well as
            ! the indices in the buffer arrays, where we temporarily store patches, if they need to be
            ! up or down sampled.
            call compute_sender_buffer_bounds(params, ijkrecv, ijksend, ijkbuffer, neighborhood, level_diff, gminus, gplus )
            ijkGhosts(1:2, 1:3, neighborhood, level_diff, SENDER) = ijksend
            ijkGhosts(1:2, 1:3, neighborhood, level_diff, RESPRE) = ijkbuffer

            ! apply a shift (if we sync only a subset of the layer)
            !
            ! g g g g g g g g g g g g        g g g g g g g g g g g g
            ! g g g g g g g g g g g g        g g g g g g g g g g g g
            ! g g g g g g g g g g g g        g g S S S S S S S S g g
            ! g g g u u u u u u g g g        g g S u u u u u u S g g
            ! g g g u u u u u u g g g        g g S u u u u u u S g g
            ! g g g u u u u u u g g g        g g S u u u u u u S g g
            ! g g g u u u u u u g g g        g g S u u u u u u S g g
            ! g g g u u u u u u g g g        g g S u u u u u u S g g
            ! g g g g g g g g g g g g        g g S S S S S S S S g g
            ! g g g g g g g g g g g g        g g g g g g g g g g g g
            ! g g g g g g g g g g g g        g g g g g g g g g g g g
            !
            ! g: ghost u: interior s: synced
            ! here, params%g=3 and g=1

            ijkGhosts(1:2,1:dim, neighborhood, level_diff,RECVER) = ijkGhosts(1:2,1:dim, neighborhood, level_diff,RECVER) + (params%g-gminus)
            ijkGhosts(1:2,1:dim, neighborhood, level_diff,SENDER) = ijkGhosts(1:2,1:dim, neighborhood, level_diff,SENDER) + (params%g-gminus)
        enddo
    enddo

    ! this output can be plotted using the python script
    if ((params%rank==0) .and. output_to_file) then
        open(16,file='ghost_bounds.dat',status='replace')
        write(16,'(i3)') params%Bs(1)
        write(16,'(i3)') params%Bs(2)
        write(16,'(i3)') params%Bs(3)
        write(16,'(i3)') params%g
        write(16,'(i3)') S
        write(16,'(i3)') A
        do neighborhood = 1, N_neighbors
            do level_diff = -1, 1
                do i = 1, 2
                    do j = 1, 3
                        do k = 1, 3
                            write(16,'(i3)') ijkGhosts(i, j, neighborhood, level_diff, k)
                        enddo
                    enddo
                enddo
            enddo
        enddo
        close(16)
    endif
end subroutine

end module module_MPI
