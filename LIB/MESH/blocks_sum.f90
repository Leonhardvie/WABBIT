! ********************************
! 2D AMR prototype
! --------------------------------
!
! absolute value summation over all nodes
! for all blocks for data field dF
!
! sum is scaled with block area and number of nodes
!
! name: blocks_sum.f90
! date: 16.08.2016
! author: msr
! version: 0.1
!
! ********************************

subroutine blocks_sum(s, dF)

    use module_params
    use module_blocks

    implicit none

    real(kind=rk), intent(inout)                :: s
    integer(kind=ik), intent(in)                :: dF

    real(kind=rk)                               :: block_s
    real(kind=rk), dimension(:,:), allocatable  :: coeff, coeff_temp
    integer                                     :: i, j, k, N, block_num, Bs, g, allocate_error

    N           = size(blocks_params%active_list, dim=1)
    Bs          = blocks_params%size_block
    g           = blocks_params%number_ghost_nodes

    allocate( coeff(Bs, Bs), stat=allocate_error )
    allocate( coeff_temp(Bs, Bs), stat=allocate_error )

    s           = 0.0_rk
    block_s     = 0.0_rk

    ! build common coefficent matrix
    coeff(:,:) = 1.0_rk
    coeff(1,:) = 0.5_rk
    coeff(Bs,:) = 0.5_rk
    coeff(:,1) = 0.5_rk
    coeff(:,Bs) = 0.5_rk
    coeff(1,1) = 0.25_rk
    coeff(Bs,Bs) = 0.25_rk
    coeff(1,Bs) = 0.25_rk
    coeff(Bs,1) = 0.25_rk

    do k = 1, N

        block_num = blocks_params%active_list(k)

        block_s = 0.0_rk
        coeff_temp = coeff

        ! block sum
        do i = 1, Bs
            do j = 1, Bs
                block_s = block_s + abs( blocks(block_num)%data_fields(dF)%data_(i+g, j+g) ) * coeff_temp(i, j)
            end do
        end do

        s = s + block_s * blocks(block_num)%dx * blocks(block_num)%dy

    end do

    deallocate( coeff, stat=allocate_error )
    deallocate( coeff_temp, stat=allocate_error )

end subroutine blocks_sum
