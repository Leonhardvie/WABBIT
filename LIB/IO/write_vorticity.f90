!> \file
!> \callgraph
! ********************************************************************************************
! WABBIT
! ============================================================================================
!> \name write_vorticity.f90
!> \version 0.5
!> \author sm
!
!> \brief compute vorticity for time step t (for writing it to disk)
!
!> \note routine uses hvy_work array for computation of vorticity, thus cannot be used during RK stages!
!!
!! input:
!!           - parameter array
!!           - light data array
!!           - heavy data array
!!
!! output:
!!           - 
!!
!!
!! = log ======================================================================================
!! \n
!! 24/07/17 - create
!
! ********************************************************************************************
subroutine write_vorticity( hvy_work, hvy_block, lgt_block, hvy_active, hvy_n, params, time, iteration, lgt_active, lgt_n)

!---------------------------------------------------------------------------------------------
! variables

    implicit none
    !> physics parameter structure
    type (type_params), intent(in)                 :: params
    !> actual block data
    real(kind=rk), intent(in)                      :: hvy_block(:, :, :, :, :)
    !> hvy_work array to safe u,v(,w) and vorticity
    real(kind=rk), intent(inout)                   :: hvy_work(:, :, :, :, :)
    !> time
    real(kind=rk), intent(in)                      :: time
    !>
    integer(kind=ik), intent(in)                   :: hvy_n, lgt_n, iteration
    !>
    integer(kind=ik), intent(in)                   :: lgt_block(:,:)
    !> list of active blocks (heavy data)
    integer(kind=ik), intent(in)                   :: hvy_active(:)
    !> list of active blocks (light data)
    integer(kind=ik), intent(inout)                :: lgt_active(:)

    !> origin and spacing of the block
    real(kind=rk), dimension(3)                    :: dx, x0
    !> local datafields
!    real(kind=rk), dimension(Bs+2*g, Bs+2*g)       :: u, v, vorticity
    ! loop variables
    integer(kind=ik)                               :: k, lgt_id
    ! file name
    character(len=80)                              :: fname

!---------------------------------------------------------------------------------------------
! variables initialization

    !vorticity = 0.0_rk
    hvy_work  = 0.0_rk

!---------------------------------------------------------------------------------------------
! main body

    do k=1, hvy_n
       call hvy_id_to_lgt_id(lgt_id, hvy_active(k), params%rank, params%number_blocks)
       call get_block_spacing_origin( params, lgt_id, lgt_block, x0, dx )
       
       if (params%threeD_case) then
           ! store u,v, w in hvy_work array
           hvy_work(:,:,:,1,hvy_active(k)) = hvy_block(:,:,:,1,hvy_active(k))  ! u
           hvy_work(:,:,:,2,hvy_active(k)) = hvy_block(:,:,:,2,hvy_active(k))  ! v
           hvy_work(:,:,:,3,hvy_active(k)) = hvy_block(:,:,:,3,hvy_active(k))  ! w
       else
           ! store u,v in hvy_work array
           hvy_work(:,:,1,1,hvy_active(k)) = hvy_block(:,:,1,1,hvy_active(k))  ! u
           hvy_work(:,:,1,2,hvy_active(k)) = hvy_block(:,:,1,2,hvy_active(k))  ! v
           !u = hvy_block(:, :, 1, hvy_active(k))
           !v = hvy_block(:, :, 2, hvy_active(k))
       end if
       
       ! compute vorticity from u,v and store it in datafield 3 of hvy_work array
       call compute_vorticity(params, hvy_work(:,:,:,1,hvy_active(k)), hvy_work(:,:,:,2,hvy_active(k)), hvy_work(:,:,:,3,hvy_active(k)), dx, hvy_work(:, :, :, 4:6, hvy_active(k)))

       ! hvy_work(:, :, 1, 1, hvy_active(k)) = vorticity(:,:)

   end do

   if (params%threeD_case) then
       ! write field 4 to 6 of hvy_work array (vorticity) to disk
       ! write vorticity in x direction
       write( fname,'(a, "_", i12.12, ".h5")') 'vor_x', nint(time * 1.0e6_rk)
       call write_field(fname, time, iteration, 4, params, lgt_block, hvy_work(:,:,:,:,:), lgt_active, lgt_n, hvy_n)
       ! write vorticity in y direction
       write( fname,'(a, "_", i12.12, ".h5")') 'vor_y', nint(time * 1.0e6_rk)
       call write_field(fname, time, iteration, 5, params, lgt_block, hvy_work(:,:,:,:,:), lgt_active, lgt_n, hvy_n)
       ! write vorticity in z direction
       write( fname,'(a, "_", i12.12, ".h5")') 'vor_z', nint(time * 1.0e6_rk)
       call write_field(fname, time, iteration, 6, params, lgt_block, hvy_work(:,:,:,:,:), lgt_active, lgt_n, hvy_n)
   else
       write( fname,'(a, "_", i12.12, ".h5")') 'vor', nint(time * 1.0e6_rk)
       ! write field 4 of hvy_work array (vorticity) to disk
       call write_field(fname, time, iteration, 4, params, lgt_block, hvy_work(:,:,:,:,:), lgt_active, lgt_n, hvy_n)
   end if

end subroutine write_vorticity