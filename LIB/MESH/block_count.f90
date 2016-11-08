! ********************************************************************************************
! WABBIT
! ============================================================================================
! name: find_neighbor_corner.f90
! version: 0.4
! author: msr
!
! count active blocks
!
! input:    - light data array
! output:   - number of active blocks
!
! = log ======================================================================================
!
! 08/11/16 - switch to v0.4
! ********************************************************************************************

subroutine block_count(block_list, block_number)

!---------------------------------------------------------------------------------------------
! modules

    ! global parameters
    use module_params

!---------------------------------------------------------------------------------------------
! variables

    implicit none

    ! light data array
    integer(kind=ik), intent(in)        :: block_list(:, :)

    ! number of active blocks
    integer(kind=ik), intent(out)       :: block_number

    ! loop variables
    integer(kind=ik)                    :: k, N

!---------------------------------------------------------------------------------------------
! variables initialization

    N               = size(block_list, 1)
    block_number    = 0

!---------------------------------------------------------------------------------------------
! main body

    ! loop over all blocks
    do k = 1, N
        if ( block_list(k, 1) /= -1 ) then
            block_number = block_number + 1
        end if
    end do

end subroutine block_count
