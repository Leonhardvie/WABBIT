! ********************************************************************************************
! WABBIT
! ============================================================================================
! name: initial_block_distribution.f90
! version: 0.4
! author: msr
!
! distribute blocks at start => create light data array
!
! input:    - parameters
!           - light block data array
!           - heavy block data array
!           - start field phi
! output:   - filled light and heavy data array
!
! todo: allow start field distribution to arbitrary datafield
!
! = log ======================================================================================
!
! 07/11/16    - switch to v0.4
! 05/12/2016  - add dummy space filling curve distribution (TODO)
!
! ********************************************************************************************

subroutine initial_block_distribution( params, lgt_block, block_data, phi )

!---------------------------------------------------------------------------------------------
! variables

    implicit none

    ! user defined parameter structure
    type (type_params), intent(in)      :: params
    ! light data array
    integer(kind=ik), intent(inout)     :: lgt_block(:, :)
    ! heavy data array - block data
    real(kind=rk), intent(inout)        :: block_data(:, :, :, :)
    ! initial data field
    real(kind=rk), intent(in)           :: phi(:, :)

    ! distribution type
    character(len=80)                   :: distribution

    ! MPI error variable
    integer(kind=ik)                    :: ierr
    ! process rank
    integer(kind=ik)                    :: rank
    ! number of processes
    integer(kind=ik)                    :: number_procs

    ! allocation error variable
    integer(kind=ik)                    :: allocate_error

    ! grid parameters (domain size, block size, number of ghost nodes
    integer(kind=ik)                    :: Ds, Bs, g
    ! block decomposition parameters
    integer(kind=ik)                    :: num_blocks_x, num_blocks_y, num_blocks
    integer(kind=ik), allocatable       :: block_proc_list(:)

    ! loop variables
    integer(kind=ik)                    :: i, j, k

    ! domain coordinate vectors
    real(kind=rk), allocatable          :: coord_x(:), coord_y(:)

    ! heavy and light data id
    integer(kind=ik)                    :: heavy_id, light_id

    ! treecode variable and function to calculate size of treecode
    integer(kind=ik), allocatable       :: treecode(:)
    integer(kind=ik)                    :: treecode_size

!---------------------------------------------------------------------------------------------
! variables initialization

    distribution    = params%block_distribution

    Ds              = params%number_domain_nodes
    Bs              = params%number_block_nodes
    g               = params%number_ghost_nodes

    ! determinate process rank
    call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
    ! determinate process number
    call MPI_Comm_size(MPI_COMM_WORLD, number_procs, ierr)

    ! allocate block to proc list
    allocate( block_proc_list( number_procs ), stat=allocate_error )

    ! allocate domain coordinate vectors
    allocate( coord_x( Ds ), stat=allocate_error )
    allocate( coord_y( Ds ), stat=allocate_error )

    ! allocate treecode
    allocate( treecode( params%max_treelevel ), stat=allocate_error )

!---------------------------------------------------------------------------------------------
! main body

    select case(distribution)
        case("equal")
            ! simple uniformly distribution

            ! calculate starting block decomposition
            ! print block decomposition information
            ! every block has two more points in a single direction (from his neighbors)
            ! therefore the complete domain has also two additional points
            num_blocks_x        = (Ds-1) / (Bs-1)
            num_blocks_y        = (Ds-1) / (Bs-1)
            num_blocks          = num_blocks_x * num_blocks_y

            ! check given domain and block size
            if ( Ds /= (num_blocks_x-1)*(Bs-1) + Bs ) then
                print*, "ERROR: blocksize do not fit into domain size"
                stop
            end if

            ! output decomposition information
            if (rank==0) then
                write(*,'(80("_"))')
                write(*,'("INIT: Field with res: ", i5, " x", i5, " gives: ", i5,  " x", i5, " (", i5, ") blocks of size: ", i5)') Ds, Ds, num_blocks_x, num_blocks_y, num_blocks, Bs
            end if

            ! decompose blocks to procs
            block_proc_list = (num_blocks - mod(num_blocks, number_procs))/number_procs
            ! distribute remaining blocks
            if (mod(num_blocks, number_procs) > 0) then
                block_proc_list(1:mod(num_blocks, number_procs)) = (num_blocks - mod(num_blocks, number_procs))/number_procs + 1
            end if

            ! calculate domain coordinate vectors
            do i = 1, Ds
                coord_x(i) = (i-1) * params%Lx / (Ds-1)
                coord_y(i) = params%Lx - (i-1) * params%Ly / (Ds-1)
            end do

            ! create block-tree
            k = 1
            do i = 1, num_blocks_x
                do j = 1, num_blocks_y
                    ! ------------------------------------------------------------------------------------------------------
                    ! write heavy data
                    ! determine proc
                    if (block_proc_list(k) == 0) then
                        k = k + 1
                        block_proc_list(k) = block_proc_list(k) - 1
                    else
                        block_proc_list(k) = block_proc_list(k) - 1
                    end if

                    ! find and set free heavy data id, note: look for free id in light data
                    ! search routine only on corresponding light data -> so, returned id works directly on heavy data
                    call get_free_light_id( heavy_id, lgt_block( (k-1)*params%number_blocks + 1 : ((k-1)+1)*params%number_blocks, 1 ), params%number_blocks )

                    ! save data, write start field phi in first datafield
                    if (rank == (k-1)) then
                        call new_block_heavy(block_data, &
                                            heavy_id, &
                                            phi( (i-1)*(Bs-1) + 1 : i*(Bs-1) + 1 , (j-1)*(Bs-1) + 1 : j*(Bs-1) + 1 ), &
                                            coord_x( (j-1)*(Bs-1) + 1 : j*(Bs-1) + 1 ), &
                                            coord_y( (i-1)*(Bs-1) + 1 : i*(Bs-1) + 1 ), &
                                            Bs, &
                                            g, &
                                            params%number_data_fields)
                    end if

                    ! ------------------------------------------------------------------------------------------------------
                    ! encoding treecode
                    call encoding(treecode, i, j, num_blocks_x, num_blocks_y, params%max_treelevel )

                    ! ------------------------------------------------------------------------------------------------------
                    ! write light data
                    ! light data id is calculated from proc rank and heavy_id
                    light_id = (k-1)*params%number_blocks + heavy_id
                    ! write treecode
                    lgt_block( light_id, 1 : params%max_treelevel ) = treecode
                    ! treecode level (size)
                    lgt_block( light_id, params%max_treelevel + 1 ) = treecode_size( treecode, params%max_treelevel )

                end do
            end do

        case("sfc_z")
            !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            ! TODO: real sfc distribution needed, actually simple uniformly distribution is used

            ! calculate starting block decomposition
            ! print block decomposition information
            ! every block has two more points in a single direction (from his neighbors)
            ! therefore the complete domain has also two additional points
            num_blocks_x        = (Ds-1) / (Bs-1)
            num_blocks_y        = (Ds-1) / (Bs-1)
            num_blocks          = num_blocks_x * num_blocks_y

            ! check given domain and block size
            if ( Ds /= (num_blocks_x-1)*(Bs-1) + Bs ) then
                print*, "ERROR: blocksize do not fit into domain size"
                stop
            end if

            ! output decomposition information
            if (rank==0) then
                write(*,'(80("_"))')
                write(*,'("INIT: Field with res: ", i5, " x", i5, " gives: ", i5,  " x", i5, " (", i5, ") blocks of size: ", i5)') Ds, Ds, num_blocks_x, num_blocks_y, num_blocks, Bs
            end if

            ! decompose blocks to procs
            block_proc_list = (num_blocks - mod(num_blocks, number_procs))/number_procs
            ! distribute remaining blocks
            if (mod(num_blocks, number_procs) > 0) then
                block_proc_list(1:mod(num_blocks, number_procs)) = (num_blocks - mod(num_blocks, number_procs))/number_procs + 1
            end if

            ! calculate domain coordinate vectors
            do i = 1, Ds
                coord_x(i) = (i-1) * params%Lx / (Ds-1)
                coord_y(i) = params%Lx - (i-1) * params%Ly / (Ds-1)
            end do

            ! create block-tree
            k = 1
            do i = 1, num_blocks_x
                do j = 1, num_blocks_y
                    ! ------------------------------------------------------------------------------------------------------
                    ! write heavy data
                    ! determine proc
                    if (block_proc_list(k) == 0) then
                        k = k + 1
                        block_proc_list(k) = block_proc_list(k) - 1
                    else
                        block_proc_list(k) = block_proc_list(k) - 1
                    end if

                    ! find and set free heavy data id, note: look for free id in light data
                    ! search routine only on corresponding light data -> so, returned id works directly on heavy data
                    call get_free_light_id( heavy_id, lgt_block( (k-1)*params%number_blocks + 1 : ((k-1)+1)*params%number_blocks, 1 ), params%number_blocks )

                    ! save data, write start field phi in first datafield
                    if (rank == (k-1)) then
                        call new_block_heavy(block_data, &
                                            heavy_id, &
                                            phi( (i-1)*(Bs-1) + 1 : i*(Bs-1) + 1 , (j-1)*(Bs-1) + 1 : j*(Bs-1) + 1 ), &
                                            coord_x( (j-1)*(Bs-1) + 1 : j*(Bs-1) + 1 ), &
                                            coord_y( (i-1)*(Bs-1) + 1 : i*(Bs-1) + 1 ), &
                                            Bs, &
                                            g, &
                                            params%number_data_fields)
                    end if

                    ! ------------------------------------------------------------------------------------------------------
                    ! encoding treecode
                    call encoding(treecode, i, j, num_blocks_x, num_blocks_y, params%max_treelevel )

                    ! ------------------------------------------------------------------------------------------------------
                    ! write light data
                    ! light data id is calculated from proc rank and heavy_id
                    light_id = (k-1)*params%number_blocks + heavy_id
                    ! write treecode
                    lgt_block( light_id, 1 : params%max_treelevel ) = treecode
                    ! treecode level (size)
                    lgt_block( light_id, params%max_treelevel + 1 ) = treecode_size( treecode, params%max_treelevel )

                end do
            end do

        case("sfc_hilbert")
            !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            ! TODO: real sfc distribution needed, actually simple uniformly distribution is used

            ! calculate starting block decomposition
            ! print block decomposition information
            ! every block has two more points in a single direction (from his neighbors)
            ! therefore the complete domain has also two additional points
            num_blocks_x        = (Ds-1) / (Bs-1)
            num_blocks_y        = (Ds-1) / (Bs-1)
            num_blocks          = num_blocks_x * num_blocks_y

            ! check given domain and block size
            if ( Ds /= (num_blocks_x-1)*(Bs-1) + Bs ) then
                print*, "ERROR: blocksize do not fit into domain size"
                stop
            end if

            ! output decomposition information
            if (rank==0) then
                write(*,'(80("_"))')
                write(*,'("INIT: Field with res: ", i5, " x", i5, " gives: ", i5,  " x", i5, " (", i5, ") blocks of size: ", i5)') Ds, Ds, num_blocks_x, num_blocks_y, num_blocks, Bs
            end if

            ! decompose blocks to procs
            block_proc_list = (num_blocks - mod(num_blocks, number_procs))/number_procs
            ! distribute remaining blocks
            if (mod(num_blocks, number_procs) > 0) then
                block_proc_list(1:mod(num_blocks, number_procs)) = (num_blocks - mod(num_blocks, number_procs))/number_procs + 1
            end if

            ! calculate domain coordinate vectors
            do i = 1, Ds
                coord_x(i) = (i-1) * params%Lx / (Ds-1)
                coord_y(i) = params%Lx - (i-1) * params%Ly / (Ds-1)
            end do

            ! create block-tree
            k = 1
            do i = 1, num_blocks_x
                do j = 1, num_blocks_y
                    ! ------------------------------------------------------------------------------------------------------
                    ! write heavy data
                    ! determine proc
                    if (block_proc_list(k) == 0) then
                        k = k + 1
                        block_proc_list(k) = block_proc_list(k) - 1
                    else
                        block_proc_list(k) = block_proc_list(k) - 1
                    end if

                    ! find and set free heavy data id, note: look for free id in light data
                    ! search routine only on corresponding light data -> so, returned id works directly on heavy data
                    call get_free_light_id( heavy_id, lgt_block( (k-1)*params%number_blocks + 1 : ((k-1)+1)*params%number_blocks, 1 ), params%number_blocks )

                    ! save data, write start field phi in first datafield
                    if (rank == (k-1)) then
                        call new_block_heavy(block_data, &
                                            heavy_id, &
                                            phi( (i-1)*(Bs-1) + 1 : i*(Bs-1) + 1 , (j-1)*(Bs-1) + 1 : j*(Bs-1) + 1 ), &
                                            coord_x( (j-1)*(Bs-1) + 1 : j*(Bs-1) + 1 ), &
                                            coord_y( (i-1)*(Bs-1) + 1 : i*(Bs-1) + 1 ), &
                                            Bs, &
                                            g, &
                                            params%number_data_fields)
                    end if

                    ! ------------------------------------------------------------------------------------------------------
                    ! encoding treecode
                    call encoding(treecode, i, j, num_blocks_x, num_blocks_y, params%max_treelevel )

                    ! ------------------------------------------------------------------------------------------------------
                    ! write light data
                    ! light data id is calculated from proc rank and heavy_id
                    light_id = (k-1)*params%number_blocks + heavy_id
                    ! write treecode
                    lgt_block( light_id, 1 : params%max_treelevel ) = treecode
                    ! treecode level (size)
                    lgt_block( light_id, params%max_treelevel + 1 ) = treecode_size( treecode, params%max_treelevel )

                end do
            end do

        case default
            write(*,'(80("_"))')
            write(*,*) "ERROR: block distribution scheme is unknown"
            write(*,*) distribution
            stop

    end select

    ! clean up
    deallocate( block_proc_list, stat=allocate_error )
    deallocate( coord_x, stat=allocate_error )
    deallocate( coord_y, stat=allocate_error )
    deallocate( treecode, stat=allocate_error )

end subroutine initial_block_distribution
