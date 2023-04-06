module module_wavelets
    use module_params

    implicit none

contains

    ! coarsen the block by one level
    subroutine restriction_2D(fine, coarse)
        implicit none

        real(kind=rk), dimension(1:,1:), intent(in) :: fine
        real(kind=rk), dimension(1:,1:), intent(out) :: coarse
        integer(kind=ik), dimension(2) :: nfine, ncoarse

        ncoarse(1) = size(coarse,1)
        ncoarse(2) = size(coarse,2)
        nfine(1)   = size(fine,1)
        nfine(2)   = size(fine,2)

#ifdef DEV
        if ( 2*ncoarse(1)-1 /= nfine(1) .or. 2*ncoarse(2)-1 /= nfine(2)) then
            write(*,*) shape(coarse), ":", shape(fine)
            call abort(888191,"ERROR: restriction_2D: arrays wrongly sized..")
        endif
#endif

        coarse(:, :) = fine(1:nfine(1):2, 1:nfine(2):2)

    end subroutine

    subroutine restriction_prefilter(params, u, u_filtered)
        implicit none
        type(type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:), intent(in) :: u
        real(kind=rk), dimension(1:,1:,1:), intent(out) :: u_filtered

        if (.not. allocated(params%HD)) call abort(71717172, "wavelet not setup")

        call blockFilterXYZ(params, u, u_filtered, params%HD, lbound(params%HD, dim=1), ubound(params%HD, dim=1))
    end subroutine


    subroutine restriction_prefilter_vct(params, u, u_filtered)
        implicit none
        type(type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:,1:), intent(in) :: u
        real(kind=rk), dimension(1:,1:,1:,1:), intent(out) :: u_filtered

        if (.not. allocated(params%HD)) call abort(71717172, "wavelet not setup")

        call blockFilterXYZ_vct(params, u, u_filtered, params%HD, lbound(params%HD, dim=1), ubound(params%HD, dim=1))
    end subroutine


    ! periodic index
    ! uses one-based indexing
    integer function perindex(i,n)
        implicit none
        integer, intent(in) :: i, n
        perindex = i
        do while (perindex<1 .or. perindex>n)
            if (perindex<1) then
                perindex = perindex+n
            elseif (perindex>n) then
                perindex = perindex-n
            endif
        end do

    end function


    ! coarsen the block by one level
    subroutine restriction_3D(fine, coarse)

        implicit none

        real(kind=rk), dimension(1:,1:,1:), intent(in)  :: fine
        real(kind=rk), dimension(1:,1:,1:), intent(out) :: coarse
        integer(kind=ik), dimension(3) :: nfine, ncoarse

        ncoarse(1) = size(coarse,1)
        ncoarse(2) = size(coarse,2)
        ncoarse(3) = size(coarse,3)
        nfine(1) = size(fine,1)
        nfine(2) = size(fine,2)
        nfine(3) = size(fine,3)

#ifdef DEV
        if ( 2*ncoarse(1)-1 /= nfine(1) .or. 2*ncoarse(2)-1 /= nfine(2) .or. 2*ncoarse(3)-1 /= nfine(3) ) then
            call abort(888192,"ERROR: restriction_3D: arrays wrongly sized..")
        endif
#endif

        coarse(:, :, :) = fine(1:nfine(1):2,1:nfine(2):2,1:nfine(3):2)

    end subroutine

    ! refine the block by one level
    subroutine prediction_2D(coarse, fine, order_predictor)
        implicit none

        real(kind=rk), dimension(1:,1:), intent(inout) :: fine
        real(kind=rk), dimension(1:,1:), intent(inout) :: coarse
        character(len=*), intent(in)                :: order_predictor

        integer(kind=ik) :: i, j, l
        integer(kind=ik) :: nxcoarse, nxfine
        integer(kind=ik) :: nycoarse, nyfine
        integer(kind=ik) :: ixfine, iyfine
        ! interpolation coefficients
        ! a: one sided, b: central
        real(kind=rk) :: a(4), b(2)

        nxcoarse = size(coarse, 1)
        nycoarse = size(coarse, 2)
        nxfine   = size(fine  , 1)
        nyfine   = size(fine  , 2)

#ifdef DEV
        if ( (2*nxcoarse-1 /= nxfine) .or. (2*nycoarse-1 /= nyfine)) then
            write(*,*) "coarse:", nxcoarse, nycoarse, "fine:", nxfine, nyfine
            call abort(888193,"ERROR: prediction_2D: arrays wrongly sized..")
        endif

        if ( ((nxfine<7) .or. (nyfine<7)).and.(order_predictor=="multiresolution_4th") ) then
            write(*,*) "coarse:", nxcoarse, nycoarse, "fine:", nxfine, nyfine
            call abort(888193,"ERROR: prediction_2D: not enough points for 4th order one-sided interp.")
        endif
#endif

        ! fill matching points: the coarse and fine grid share a lot of points (as the
        ! fine grid results from insertion of one point between each coarse point)
        fine(1:nxfine:2, 1:nyfine:2) = coarse(:,:)


        if ( order_predictor == "multiresolution_2nd" ) then
            !-------------------------------------------------------------------
            ! second order interpolation
            !-------------------------------------------------------------------
            ! y direction
            do i = 2, nxfine, 2
                do j = 1, nyfine, 2
                    fine(i,j) = ( fine(i-1, j) + fine(i+1, j) ) * 0.5_rk
                end do
            end do

            ! x direction
            do i = 1, nxfine
                do j = 2, nyfine, 2
                    fine(i,j) = ( fine(i, j-1) + fine(i, j+1) ) * 0.5_rk
                end do
            end do

        elseif ( order_predictor == "multiresolution_4th"  ) then
            !-------------------------------------------------------------------
            ! fourth order interpolation
            !-------------------------------------------------------------------
            ! one-side coeffs:
            a = (/ 5.0_rk/16.0_rk, 15.0_rk/16.0_rk, -5.0_rk/16.0_rk, 1.0_rk/16.0_rk /)
            ! centered coeffs (symmetric)
            b = (/ 9.0_rk/16.0_rk, -1.0_rk/16.0_rk /)

            ! step (a)
            ! first columns (x: const y: variable )
            ! these points require one-sided interpolation.
            fine( 2, 1:nyfine:2 ) = &
            a(1)*fine( 1, 1:nyfine:2 ) &
            + a(2)*fine( 3, 1:nyfine:2 ) &
            + a(3)*fine( 5, 1:nyfine:2 ) &
            + a(4)*fine( 7, 1:nyfine:2 )

            ! last column (same as above)
            fine( nxfine-1, 1:nyfine:2 ) = &
            a(4)*fine( nxfine-6, 1:nyfine:2 ) &
            + a(3)*fine( nxfine-4, 1:nyfine:2 ) &
            + a(2)*fine( nxfine-2, 1:nyfine:2 ) &
            + a(1)*fine( nxfine,   1:nyfine:2 )

            ! interpolate regular columns
            do ixfine =  4, nxfine-3, 2
                fine( ixfine, 1:nyfine:2 ) = &
                b(2)*fine( ixfine-3, 1:nyfine:2 ) &
                + b(1)*fine( ixfine-1, 1:nyfine:2 ) &
                + b(1)*fine( ixfine+1, 1:nyfine:2 ) &
                + b(2)*fine( ixfine+3, 1:nyfine:2 )
            enddo


            ! At this point, we have only every 2nd complete row missing
            ! so from now on, no step size 2 anymore

            ! first row
            ! these points require one-sided interpolation.
            fine( 1:nxfine, 2 ) = a(1)*fine( 1:nxfine, 1 ) &
            + a(2)*fine( 1:nxfine, 3 ) &
            + a(3)*fine( 1:nxfine, 5 ) &
            + a(4)*fine( 1:nxfine, 7 )

            ! last row (same as above)
            fine( 1:nxfine, nyfine-1 ) = a(4)*fine( 1:nxfine, nyfine-6) &
            + a(3)*fine( 1:nxfine, nyfine-4 ) &
            + a(2)*fine( 1:nxfine, nyfine-2 ) &
            + a(1)*fine( 1:nxfine, nyfine )

            ! remaining interior rows
            do iyfine =  4, nyfine-3, 2
                fine( 1:nxfine, iyfine ) = b(2)*fine( 1:nxfine, iyfine-3 ) &
                + b(1)*fine( 1:nxfine, iyfine-1 ) &
                + b(1)*fine( 1:nxfine, iyfine+1 ) &
                + b(2)*fine( 1:nxfine, iyfine+3 )
            enddo

        else
            ! error case
            call abort(888194,"ERROR: prediction_2D: wrong method..")
        endif

    end subroutine


    ! refine the block by one level
    subroutine prediction_3D(coarse, fine, order_predictor)
        implicit none

        real(kind=rk), dimension(1:,1:,1:), intent(inout) :: fine
        real(kind=rk), dimension(1:,1:,1:), intent(inout) :: coarse
        character(len=*), intent(in) :: order_predictor

        integer(kind=ik) :: i, j, k
        integer(kind=ik) :: nxcoarse, nxfine, nycoarse, nyfine, nzcoarse, nzfine
        integer(kind=ik) :: ixfine, iyfine, izfine
        ! interpolation coefficients
        ! a: one sided, b: central
        real(kind=rk) :: a(4), b(2)

        nxcoarse = size(coarse, 1)
        nxfine   = size(fine  , 1)
        nycoarse = size(coarse, 2)
        nyfine   = size(fine  , 2)
        nzcoarse = size(coarse, 3)
        nzfine   = size(fine  , 3)

        if ( 2*nxcoarse-1 /= nxfine .or. 2*nycoarse-1 /= nyfine .or. 2*nzcoarse-1 /= nzfine ) then
            call abort(888195,"ERROR: prediction_3D: arrays wrongly sized..")
        endif

        ! fill matching points: the coarse and fine grid share a lot of points (as the
        ! fine grid results from insertion of one point between each coarse point)
        fine(1:nxfine:2, 1:nyfine:2, 1:nzfine:2) = coarse(:, :, :)

        if ( order_predictor == "multiresolution_2nd" ) then
            !-------------------------------------------------------------------
            ! second order interpolation
            !-------------------------------------------------------------------
            ! y direction
            do k = 1, nzfine, 2
                do j = 1, nyfine, 2
                    do i = 2, nxfine, 2
                        fine(i,j,k) = ( fine(i-1, j, k) + fine(i+1, j, k) ) * 0.5_rk
                    end do
                end do
            end do

            ! x direction
            do k = 1, nzfine, 2
                do j = 2, nyfine, 2
                    do i = 1, nxfine
                        fine(i,j,k) = ( fine(i, j-1, k) + fine(i, j+1, k) ) * 0.5_rk
                    end do
                end do
            end do

            ! z direction
            do k = 2, nzfine, 2
                do j = 1, nyfine
                    do i = 1, nxfine
                        fine(i,j,k) = ( fine(i, j, k-1) + fine(i, j, k+1) ) * 0.5_rk
                    end do
                end do
            end do

        elseif ( order_predictor == "multiresolution_4th"  ) then
            !-----------------------------------------------------------------------
            ! fourth order interpolation
            !-----------------------------------------------------------------------
            ! one-side coeffs:
            a = (/ 5.0_rk/16.0_rk, 15.0_rk/16.0_rk, -5.0_rk/16.0_rk, 1.0_rk/16.0_rk /)
            ! centered coeffs (symmetric)
            b = (/ 9.0_rk/16.0_rk, -1.0_rk/16.0_rk /)

            do izfine = 1, nzfine, 2
                ! --> in the planes, execute the 2d code
                ! step (a)
                ! first columns (x: const y: variable )
                ! these points requie one-sided interpolation.
                fine( 2, 1:nyfine:2, izfine ) = a(1)*fine( 1, 1:nyfine:2, izfine ) &
                + a(2)*fine( 3, 1:nyfine:2, izfine ) &
                + a(3)*fine( 5, 1:nyfine:2, izfine ) &
                + a(4)*fine( 7, 1:nyfine:2, izfine )

                ! last columns (same as above)
                fine( nxfine-1, 1:nyfine:2, izfine ) = a(4)*fine( nxfine-6, 1:nyfine:2, izfine ) &
                + a(3)*fine( nxfine-4, 1:nyfine:2, izfine ) &
                + a(2)*fine( nxfine-2, 1:nyfine:2, izfine ) &
                + a(1)*fine( nxfine,   1:nyfine:2, izfine )

                ! interpolate regular columns
                do ixfine =  4, nxfine-3, 2
                    fine( ixfine, 1:nyfine:2, izfine ) = b(2)*fine( ixfine-3, 1:nyfine:2, izfine ) &
                    + b(1)*fine( ixfine-1, 1:nyfine:2, izfine ) &
                    + b(1)*fine( ixfine+1, 1:nyfine:2, izfine ) &
                    + b(2)*fine( ixfine+3, 1:nyfine:2, izfine )
                enddo


                ! At this point, we have only every 2nd complete row missing
                ! so from now on, no step size 2 anymore

                ! first row
                ! these points requie one-sided interpolation.
                fine( 1:nxfine, 2, izfine ) = a(1)*fine( 1:nxfine, 1, izfine ) &
                + a(2)*fine( 1:nxfine, 3, izfine ) &
                + a(3)*fine( 1:nxfine, 5, izfine ) &
                + a(4)*fine( 1:nxfine, 7, izfine )
                ! last row (same as above)
                fine( 1:nxfine, nyfine-1, izfine ) = a(4)*fine( 1:nxfine, nyfine-6, izfine ) &
                + a(3)*fine( 1:nxfine, nyfine-4, izfine ) &
                + a(2)*fine( 1:nxfine, nyfine-2, izfine ) &
                + a(1)*fine( 1:nxfine, nyfine, izfine )
                ! remaining interior rows
                do iyfine =  4, nyfine-3, 2
                    fine( 1:nxfine, iyfine, izfine ) = b(2)*fine( 1:nxfine, iyfine-3, izfine ) &
                    + b(1)*fine( 1:nxfine, iyfine-1, izfine ) &
                    + b(1)*fine( 1:nxfine, iyfine+1, izfine ) &
                    + b(2)*fine( 1:nxfine, iyfine+3, izfine )
                enddo
            enddo

            ! interpolate the z-direction (completely missing planes, no step 2)
            ! first plane
            fine( :, :, 2 ) = a(1)*fine( :, :, 1 ) &
            + a(2)*fine( :, :, 3 ) &
            + a(3)*fine( :, :, 5 ) &
            + a(4)*fine( :, :, 7 )
            ! last plane
            fine( :, :, nzfine-1 ) = a(4)*fine( :, :, nzfine-6 ) &
            + a(3)*fine( :, :, nzfine-4 ) &
            + a(2)*fine( :, :, nzfine-2 ) &
            + a(1)*fine( :, :, nzfine )
            ! remaining planes
            do izfine =  4, nzfine-3, 2
                fine( :, :, izfine ) = b(2)*fine( :, :, izfine-3 ) &
                + b(1)*fine( :, :, izfine-1 ) &
                + b(1)*fine( :, :, izfine+1 ) &
                + b(2)*fine( :, :, izfine+3 )
            enddo


        else
            ! error case
            call abort(888196,"ERROR: prediction_2D: wrong method..")
        endif

    end subroutine


    ! Please note applying a filter requires also manipulating the ghost nodes
    subroutine blockFilterXYZ( params, u, u_filtered, coefs_filter, a, b )
        implicit none
        type (type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:), intent(in) :: u
        real(kind=rk), dimension(1:,1:,1:), intent(inout) :: u_filtered
        integer(kind=ik) :: a, b
        real(kind=rk), intent(in) :: coefs_filter(a:b)
        integer(kind=ik) :: ix, iy, iz, nx, ny, nz, shift, g, Bs(1:3)
        real(kind=rk), allocatable, save :: u_tmp(:,:,:)

        ! if the filter is just 1, then we copy and we're done.
        ! Yes, we use such stupid filters. They are in the CDFX0 wavelets (X=2,4)
        if (a==0 .and. b==0 .and. coefs_filter(0)==1.0_rk) then
            u_filtered = u
            return
        endif

        nx = size(u, 1)
        ny = size(u, 2)
        nz = size(u, 3)
        g  = params%g
        Bs = params%Bs

        if ((abs(a) > g).or.(b>g)) then
            write(*,*) a, b, "but g=", g
            call abort(202302209, "For applying the filter, not enough ghost nodes")
        endif

        if (.not. allocated(u_tmp)) allocate( u_tmp(1:nx,1:ny,1:nz) )
        u_tmp = u

        u_filtered = u_tmp
        u_filtered(g+1:Bs(1)+g, :, :) = 0.0_rk
        do ix = g+1, Bs(1)+g
            ! do ix = -a+1, nx-b
            do shift = a, b
                u_filtered(ix, :, :) = u_filtered(ix, :, :) + u_tmp(ix+shift, :, :)*coefs_filter(shift)
            enddo
        enddo

        u_tmp = u_filtered
        u_filtered = u_tmp
        u_filtered(:, g+1:Bs(2)+g, :) = 0.0_rk
        do iy = g+1, Bs(2)+g
            ! do iy = -a+1, ny-b
            do shift = a, b
                u_filtered(:, iy, :) = u_filtered(:, iy, :) + u_tmp(:, iy+shift, :)*coefs_filter(shift)
            enddo
        enddo

        if (nz == 1) return

        u_tmp = u_filtered
        u_filtered = u_tmp
        u_filtered(:, :, g+1:Bs(3)+g) = 0.0_rk
        do iz = g+1, Bs(3)+g
            do shift = a, b
                u_filtered(:, :, iz) = u_filtered(:, :, iz) + u_tmp(:, :, iz+shift)*coefs_filter(shift)
            enddo
        enddo

    end subroutine

    subroutine blockFilterXYZ_vct( params, u, u_filtered, coefs_filter, a, b)
        implicit none
        type (type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:,1:), intent(in) :: u
        real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u_filtered
        integer(kind=ik) :: a, b
        real(kind=rk), intent(in) :: coefs_filter(a:b)
        integer(kind=ik) :: ix, iy, iz, nx, ny, nz, nc, shift, g, Bs(1:3)
        real(kind=rk), allocatable, save :: u_tmp(:,:,:,:)

        ! if the filter is just 1, then we copy and we're done.
        ! Yes, we use such stupid filters. They are in the CDFX0 wavelets (X=2,4)
        if (a==0 .and. b==0 .and. coefs_filter(0)==1.0_rk) then
            u_filtered = u
            return
        endif


        nx = size(u, 1)
        ny = size(u, 2)
        nz = size(u, 3)
        nc = size(u, 4)
        g  = params%g
        Bs = params%Bs

        if ((abs(a) > g).or.(b>g)) then
            write(*,*) a, b, "but g=", g
            call abort(202302209, "For applying the filter, not enough ghost nodes")
        endif

        if (.not. allocated(u_tmp)) allocate( u_tmp(1:nx,1:ny,1:nz,1:nc) )
        u_tmp = u

        u_filtered = u_tmp
        u_filtered(g+1:Bs(1)+g, :, :, :) = 0.0_rk
        do ix = g+1, Bs(1)+g
            do shift = a, b
                u_filtered(ix, :, :, :) = u_filtered(ix, :, :, :) + u_tmp(ix+shift, :, :, :)*coefs_filter(shift)
            enddo
        enddo

        u_tmp = u_filtered
        u_filtered = u_tmp
        u_filtered(:, g+1:Bs(2)+g, :, :) = 0.0_rk
        do iy = g+1, Bs(2)+g
            do shift = a, b
                u_filtered(:, iy, :, :) = u_filtered(:, iy, :, :) + u_tmp(:, iy+shift, :, :)*coefs_filter(shift)
            enddo
        enddo


        if (nz == 1) return

        u_tmp = u_filtered
        u_filtered = u_tmp
        u_filtered(:, :, g+1:Bs(3)+g, :) = 0.0_rk
        do iz = g+1, Bs(3)+g
            do shift = a, b
                u_filtered(:, :, iz, :) = u_filtered(:, :, iz, :) + u_tmp(:, :, iz+shift, :)*coefs_filter(shift)
            enddo
        enddo

    end subroutine


    ! apply the filter only inside the block, where the filter coefficients are
    ! not reaching into the ghost nodes layer.
    subroutine blockFilterXYZ_interior_vct( u, u_filtered, coefs_filter, a, b, g)
        implicit none
        real(kind=rk), dimension(1:,1:,1:,1:), intent(in) :: u
        real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u_filtered
        integer(kind=ik) :: a, b, g
        real(kind=rk), intent(in) :: coefs_filter(a:b)
        integer(kind=ik) :: ix, iy, iz, nx, ny, nz, nc, shift
        real(kind=rk), allocatable :: u_tmp(:,:,:,:)

        ! if the filter is just 1, then we copy and we're done.
        ! Yes, we use such stupid filters. They are in the CDFX0 wavelets (X=2,4)
        if (a==0 .and. b==0 .and. coefs_filter(0)==1.0_rk) then
            u_filtered = u
            return
        endif

        nx = size(u, 1)
        ny = size(u, 2)
        nz = size(u, 3)
        nc = size(u, 4)

        allocate( u_tmp(1:nx,1:ny,1:nz,1:nc) )
        u_tmp = u

        u_filtered = u_tmp
        u_filtered(-a+1+g:nx-b-g, :, :, :) = 0.0_rk
        do ix = -a+1+g, nx-b-g
            do shift = a, b
                u_filtered(ix, :, :, :) = u_filtered(ix, :, :, :) + u_tmp(ix+shift, :, :, :)*coefs_filter(shift)
            enddo
        enddo

        u_tmp = u_filtered
        u_filtered = u_tmp
        u_filtered(:, -a+1+g:ny-b-g, :, :) = 0.0_rk
        do iy = -a+1+g, ny-b-g
            do shift = a, b
                u_filtered(:, iy, :, :) = u_filtered(:, iy, :, :) + u_tmp(:, iy+shift, :, :)*coefs_filter(shift)
            enddo
        enddo


        if (nz == 1) return

        u_tmp = u_filtered
        u_filtered = u_tmp
        u_filtered(:, :, -a+1+g:nz-b-g, :) = 0.0_rk
        do iz = -a+1+g, nz-b-g
            do shift = a, b
                u_filtered(:, :, iz, :) = u_filtered(:, :, iz, :) + u_tmp(:, :, iz+shift, :)*coefs_filter(shift)
            enddo
        enddo

        deallocate(u_tmp)
    end subroutine

    ! applies one of params% HD GD HR GR filters in each direction
    subroutine blockFilterCustom_vct( params, u, u_filtered, filter_x, filter_y, filter_z )
        implicit none
        type (type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:,1:), intent(in) :: u
        real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u_filtered
        character(len=*), intent(in) :: filter_x, filter_y, filter_z
        integer(kind=ik) :: a, b
        real(kind=rk), allocatable :: coefs_filter(:)
        integer(kind=ik) :: ix, iy, iz, nx, ny, nz, nc, shift, g, Bs(1:3)
        real(kind=rk), allocatable, save :: u_tmp(:,:,:,:)

        nx = size(u, 1)
        ny = size(u, 2)
        nz = size(u, 3)
        nc = size(u, 4)
        g  = params%g
        Bs = params%Bs

        !-----------------------------------------------------------------------
        ! Filter x
        !-----------------------------------------------------------------------
        if (.not. allocated(u_tmp)) allocate( u_tmp(1:nx, 1:ny, 1:nz, 1:nc) )
        u_tmp = u

        select case(filter_x)
        case("HD")
            if (.not. allocated(params%HD)) call abort(202302203, "Wavelet setup not done yet?! HD")
            a = lbound(params%HD, dim=1)
            b = ubound(params%HD, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%HD

        case("GD")
            if (.not. allocated(params%GD)) call abort(202302203, "Wavelet setup not done yet?! GD")
            a = lbound(params%GD, dim=1)
            b = ubound(params%GD, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%GD

        case("HR")
            if (.not. allocated(params%HR)) call abort(202302203, "Wavelet setup not done yet?! HR")
            a = lbound(params%HR, dim=1)
            b = ubound(params%HR, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%HR

        case("GR")
            if (.not. allocated(params%GR)) call abort(202302203, "Wavelet setup not done yet?! GR")
            a = lbound(params%GR, dim=1)
            b = ubound(params%GR, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%GR

        case default
            call abort(202302201, "Unknown wavelet filter, must be one of HD GD HR GR")

        end select

        if ((abs(a) > g).or.(b>g)) then
            write(*,*) a, b, "but g=", g
            call abort(202302211, "For applying the filter, not enough ghost nodes")
        endif

        u_filtered = u_tmp
        u_filtered(g+1:Bs(1)+g, :, :, :) = 0.0_rk
        do ix = g+1, Bs(1)+g
            do shift = a, b
                u_filtered(ix, :, :, :) = u_filtered(ix, :, :, :) + u_tmp(ix+shift, :, :, :)*coefs_filter(shift)
            enddo
        enddo

        !-----------------------------------------------------------------------
        ! Filter y
        !-----------------------------------------------------------------------
        select case(filter_y)
        case("HD")
            a = lbound(params%HD, dim=1)
            b = ubound(params%HD, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%HD

        case("GD")
            a = lbound(params%GD, dim=1)
            b = ubound(params%GD, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%GD

        case("HR")
            a = lbound(params%HR, dim=1)
            b = ubound(params%HR, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%HR

        case("GR")
            a = lbound(params%GR, dim=1)
            b = ubound(params%GR, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%GR

        case default
            call abort(202302201, "Unknown wavelet filter, must be one of HD GD HR GR")

        end select

        if ((abs(a) > g).or.(b>g)) then
            write(*,*) a, b, "but g=", g
            call abort(202302211, "For applying the filter, not enough ghost nodes")
        endif

        u_tmp = u_filtered
        u_filtered = u_tmp
        u_filtered(:, g+1:Bs(2)+g, :, :) = 0.0_rk
        do iy = g+1, Bs(2)+g
            do shift = a, b
                u_filtered(:, iy, :, :) = u_filtered(:, iy, :, :) + u_tmp(:, iy+shift, :, :)*coefs_filter(shift)
            enddo
        enddo

        !-----------------------------------------------------------------------
        ! Filter z
        !-----------------------------------------------------------------------
        if (nz == 1) return

        select case(filter_z)
        case("HD")
            a = lbound(params%HD, dim=1)
            b = ubound(params%HD, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%HD

        case("GD")
            a = lbound(params%GD, dim=1)
            b = ubound(params%GD, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%GD

        case("HR")
            a = lbound(params%HR, dim=1)
            b = ubound(params%HR, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%HR

        case("GR")
            a = lbound(params%GR, dim=1)
            b = ubound(params%GR, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%GR

        case ("--")
            return

        case default
            call abort(202302201, "Unknown wavelet filter, must be one of HD GD HR GR")

        end select

        if ((abs(a) > g).or.(b>g)) then
            write(*,*) a, b, "but g=", g
            call abort(202302211, "For applying the filter, not enough ghost nodes")
        endif

        u_tmp = u_filtered
        u_filtered = u_tmp
        u_filtered(:, :, g+1:Bs(3)+g, :) = 0.0_rk
        do iz = g+1, Bs(3)+g
            do shift = a, b
                u_filtered(:, :, iz, :) = u_filtered(:, :, iz, :) + u_tmp(:, :, iz+shift, :)*coefs_filter(shift)
            enddo
        enddo

    end subroutine

    !-------------------------------------------------------------------------------
    ! applies one of params% HD GD HR GR filters in one direction
    subroutine blockFilterCustom1_vct( params, u, u_filtered, filter, direction )
        implicit none
        type (type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:,1:), intent(in) :: u
        real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u_filtered
        character(len=*), intent(in) :: filter, direction
        integer(kind=ik) :: a, b
        real(kind=rk), allocatable :: coefs_filter(:)
        integer(kind=ik) :: ix, iy, iz, nx, ny, nz, nc, shift, g, Bs(1:3)
        real(kind=rk), allocatable, save :: u_tmp(:,:,:,:)

        nx = size(u, 1)
        ny = size(u, 2)
        nz = size(u, 3)
        nc = size(u, 4)
        g  = params%g
        Bs = params%Bs

        if (.not. allocated(u_tmp)) allocate( u_tmp(1:nx, 1:ny, 1:nz, 1:nc) )
        u_tmp = u

        select case(filter)
        case("HD")
            if (.not. allocated(params%HD)) call abort(202302203, "Wavelet setup not done yet?! HD")
            a = lbound(params%HD, dim=1)
            b = ubound(params%HD, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%HD

        case("GD")
            if (.not. allocated(params%GD)) call abort(202302203, "Wavelet setup not done yet?! GD")
            a = lbound(params%GD, dim=1)
            b = ubound(params%GD, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%GD

        case("HR")
            if (.not. allocated(params%HR)) call abort(202302203, "Wavelet setup not done yet?! HR")
            a = lbound(params%HR, dim=1)
            b = ubound(params%HR, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%HR

        case("GR")
            if (.not. allocated(params%GR)) call abort(202302203, "Wavelet setup not done yet?! GR")
            a = lbound(params%GR, dim=1)
            b = ubound(params%GR, dim=1)
            if (allocated(coefs_filter)) deallocate(coefs_filter)
            allocate( coefs_filter(a:b) )
            coefs_filter = params%GR

        case default
            call abort(202302201, "Unknown wavelet filter, must be one of HD GD HR GR")

        end select

        if ((abs(a) > g).or.(b>g)) then
            write(*,*) a, b, "but g=", g
            call abort(202302211, "For applying the filter, not enough ghost nodes")
        endif

        select case(direction)
        case("x")
            u_filtered = u_tmp
            u_filtered(g+1:Bs(1)+g, :, :, :) = 0.0_rk
            do ix = g+1, Bs(1)+g
                do shift = a, b
                    u_filtered(ix, :, :, :) = u_filtered(ix, :, :, :) + u_tmp(ix+shift, :, :, :)*coefs_filter(shift)
                enddo
            enddo

        case("y")
            u_filtered = u_tmp
            u_filtered(:, g+1:Bs(2)+g, :, :) = 0.0_rk
            do iy = g+1, Bs(2)+g
                do shift = a, b
                    u_filtered(:, iy, :, :) = u_filtered(:, iy, :, :) + u_tmp(:, iy+shift, :, :)*coefs_filter(shift)
                enddo
            enddo

        case("z")
            u_filtered = u_tmp
            u_filtered(:, :, g+1:Bs(3)+g, :) = 0.0_rk
            do iz = g+1, Bs(3)+g
                do shift = a, b
                    u_filtered(:, :, iz, :) = u_filtered(:, :, iz, :) + u_tmp(:, :, iz+shift, :)*coefs_filter(shift)
                enddo
            enddo

        case default
            call abort(202302201, "Unknown direction [xyz]. You should go to bed more early, its better.")

        end select


    end subroutine

    !-------------------------------------------------------------------------------

    ! computes a one-level wavelet decomposition of a block.
    ! The computation of coefficients is possible on the entire block, but
    ! without sync'ing the reconstruction is not possible on the entire data.
    ! We have to sync wavelet-transformed blocks.
    ! Data are stored in Spaghetti-order (not Mallat-Order)
    subroutine waveletDecomposition_block(params, u)
        implicit none
        type (type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u

        real(kind=rk), allocatable, dimension(:,:,:,:), save :: sc, wc, test, ucopy
        integer(kind=ik) :: nx, ny, nz, nc, g, Bs(1:3), ii
        ! integer(kind=ik) :: ag, bg, ah, bh, ix, iy, iz, ic, shift
        ! real(kind=rk) :: ug, uh

        call WaveDecomposition_dim1( params, u )
    end subroutine


    ! computes a one-level wavelet decomposition of a block.
    ! The computation of coefficients is possible on the entire block, but
    ! without sync'ing the reconstruction is not possible on the entire data.
    ! We have to sync wavelet-transformed blocks.
    ! Data are stored in Spaghetti-order (not Mallat-Order)
    subroutine waveletDecomposition_block_old(params, u)
        implicit none
        type (type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u

        real(kind=rk), allocatable, dimension(:,:,:,:), save :: sc, wc, test, ucopy
        integer(kind=ik) :: nx, ny, nz, nc, g, Bs(1:3), ii
        ! integer(kind=ik) :: ag, bg, ah, bh, ix, iy, iz, ic, shift
        ! real(kind=rk) :: ug, uh

        nx = size(u, 1)
        ny = size(u, 2)
        nz = size(u, 3)
        nc = size(u, 4)
        g  = params%g
        Bs = params%Bs

#ifdef DEV
        if (nz /= 1) call abort(7223839, "currently 2D only")
        if (modulo(Bs(1),2)/=0) call abort(7223139, "only even Bs is possible with biorthogonal wavelets")
        if (modulo(Bs(2),2)/=0) call abort(7223139, "only even Bs is possible with biorthogonal wavelets")
#endif

        if (allocated(sc)) then
            if ((size(sc,1)/=nx).or.(size(sc,2)/=ny).or.(size(sc,3)/=nz).or.(size(sc,4)/=nc)) deallocate(sc)
        endif
        if (allocated(wc)) then
            if ((size(wc,1)/=nx).or.(size(wc,2)/=ny).or.(size(wc,3)/=nz).or.(size(wc,4)/=nc)) deallocate(wc)
        endif

        if (.not. allocated(sc)) allocate( sc(1:nx, 1:ny, 1:nz, 1:nc) )
        if (.not. allocated(wc)) allocate( wc(1:nx, 1:ny, 1:nz, 1:nc) )
        ! if (.not. allocated(u_wc)) allocate( u_wc(1:nx, 1:ny, 1:nz, 1:nc) )

        ! alternative algorithm (true Mallat ordering, but with ghost nodes)
        call blockFilterCustom1_vct( params, u, sc, "HD", "x" )
        call blockFilterCustom1_vct( params, u, wc, "GD", "x" )

        u( 1:Bs(1)/2, :, :, :)       = sc( (g+1):(Bs(1)+g):2, :, :, :)
        u( Bs(1)/2+1:Bs(1), :, :, :) = wc( (g+1):(Bs(1)+g):2, :, :, :)

        call blockFilterCustom1_vct( params, u, sc, "HD", "y" )
        call blockFilterCustom1_vct( params, u, wc, "GD", "y" )

        u(:, 1:Bs(2)/2, :, :) =  sc(:, (g+1):(Bs(2)+g):2, :, :)
        u(:, Bs(2)/2+1:Bs(2), :, :) = wc(:, (g+1):(Bs(2)+g):2, :, :)

        ! Note at this point U contains SC/WC in "true Mallat ordering", but note
        ! that data includes ghost nodes.

        ! copy to Spaghetti ordering
        sc=0.0_rk
        sc( (g+1):(Bs(1)+g):2, (g+1):(Bs(1)+g):2, :, :) = u(1:Bs(1)/2, 1:Bs(2)/2, :, :)
        sc( (g+2):(Bs(1)+g):2, (g+1):(Bs(1)+g):2, :, :) = u(1:Bs(1)/2, Bs(2)/2+1:Bs(2), :, :)
        sc( (g+1):(Bs(1)+g):2, (g+2):(Bs(1)+g):2, :, :) = u(Bs(1)/2+1:Bs(1), 1:Bs(2)/2, :, :)
        sc( (g+2):(Bs(1)+g):2, (g+2):(Bs(1)+g):2, :, :) = u(Bs(1)/2+1:Bs(1), Bs(2)/2+1:Bs(2), :, :)

        ! copy to the back spaghetti-ordered coefficients to the block
        u = sc
    end subroutine

    !-------------------------------------------------------------------------------

    subroutine waveletReconstruction_block(params, u)
        implicit none
        type (type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u

        call WaveReconstruction_dim1( params, u )
    end subroutine

    !-------------------------------------------------------------------------------

!     subroutine waveletReconstruction_block_old(params, u)
!         implicit none
!         type (type_params), intent(in) :: params
!         real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u
!
!         real(kind=rk), allocatable, dimension(:,:,:,:,:), save :: wc
!         integer(kind=ik) :: nx, ny, nz, nc, g, Bs(1:3)
!
!         nx = size(u, 1)
!         ny = size(u, 2)
!         nz = size(u, 3)
!         nc = size(u, 4)
!         g  = params%g
!         Bs = params%Bs
!
!         if (allocated(sc)) then
!             if ((size(sc,1)/=nx).or.(size(sc,2)/=ny).or.(size(sc,3)/=nz).or.(size(sc,4)/=nc)) deallocate(sc)
!         endif
!         if (allocated(wcx)) then
!             if ((size(wcx,1)/=nx).or.(size(wcx,2)/=ny).or.(size(wcx,3)/=nz).or.(size(wcx,4)/=nc)) deallocate(wcx)
!         endif
!         if (allocated(wcy)) then
!             if ((size(wcy,1)/=nx).or.(size(wcy,2)/=ny).or.(size(wcy,3)/=nz).or.(size(wcy,4)/=nc)) deallocate(wcy)
!         endif
!         if (allocated(wcxy)) then
!             if ((size(wcxy,1)/=nx).or.(size(wcxy,2)/=ny).or.(size(wcxy,3)/=nz).or.(size(wcxy,4)/=nc)) deallocate(wcxy)
!         endif
!
!         if (.not. allocated(sc  )) allocate(   sc(1:nx, 1:ny, 1:nz, 1:nc) )
!         if (.not. allocated(wcx )) allocate(  wcx(1:nx, 1:ny, 1:nz, 1:nc) )
!         if (.not. allocated(wcy )) allocate(  wcy(1:nx, 1:ny, 1:nz, 1:nc) )
!         if (.not. allocated(wcxy)) allocate( wcxy(1:nx, 1:ny, 1:nz, 1:nc) )
!
! #ifdef DEV
!         if (nz /= 1) call abort(7223839, "currently 2D only")
!         if (modulo(Bs(1), 2) /= 0) call abort(99111,"This code requires Bs even")
!         if (modulo(Bs(2), 2) /= 0) call abort(99111,"This code requires Bs even")
! #endif
!
!         call spaghetti2inflatedMallat_block(params, u, sc, wcx, wcy, wcxy)
!
!         call blockFilterCustom_vct( params, sc  , sc  , "HR", "HR", "--" ) ! inplace should work, only a copy statement from the input
!         call blockFilterCustom_vct( params, wcx , wcx , "HR", "GR", "--" ) ! inplace should work, only a copy statement from the input
!         call blockFilterCustom_vct( params, wcy , wcy , "GR", "HR", "--" ) ! inplace should work, only a copy statement from the input
!         call blockFilterCustom_vct( params, wcxy, wcxy, "GR", "GR", "--" ) ! inplace should work, only a copy statement from the input
!
!         u = sc + wcx + wcy + wcxy
!     end subroutine

    !-------------------------------------------------------------------------------

    ! ensures that 3/4 of the numbers are zero - required for reconstruction
    ! note when copying Spaghetti to Mallat, this is automatically done, but
    ! when manipulating coefficients, it may happen that we set nonzero values
    ! where a zero should be.
    subroutine setRequiredZerosWCSC_block(params, u)
        implicit none
        type (type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u

        integer(kind=ik) :: nx, ny

        nx = size(u, 1)
        ny = size(u, 2)

        if (modulo(params%g, 2) == 0) then
            ! even ghost nodes: 2nd coefficient will be set to zero
            !
            ! x 0 x 0 x 0
            ! 0 0 0 0 0 0
            ! x 0 x 0 x 0
            !
            u(2:nx:2, 2:ny:2, :, :) = 0.0_rk ! diagonal
            u(2:nx:2, 1:ny:2, :, :) = 0.0_rk ! to the right (+x)
            u(1:nx:2, 2:ny:2, :, :) = 0.0_rk ! to the top (+y)
        else
            ! odd ghost nodes: 1st coefficient will be set to zero
            !
            ! 0 0 0 0 0
            ! 0 x 0 x 0
            ! 0 0 0 0 0
            ! 0 x 0 x 0
            !
            u(1:nx:2, 1:ny:2, :, :) = 0.0_rk ! diagonal
            u(1:nx:2, 2:ny:2, :, :) = 0.0_rk ! +y
            u(2:nx:2, 1:ny:2, :, :) = 0.0_rk ! +x
        endif


    end subroutine

    ! Inflated Mallat ordering is a HACK. I was just easier to code.
    ! That does not mean its wrong, it isn't. But is uses extra memory (although
    ! that is negligible) and does unnecessary copy actions.
    subroutine spaghetti2inflatedMallat_block(params, u, wc)
        implicit none
        type (type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u
        ! The WC array contains SC (scaling function coeffs) as well as all WC (wavelet coeffs)
        ! Note: the precise naming of SC/WC is not really important. we just apply
        ! the correct decomposition/reconstruction filters - thats it.
        !
        ! INDEX            2D     3D     LABEL
        ! -----            --    ---     ---------------------------------
        ! wc(:,:,:,:,1)    HH    HHH     sc scaling function coeffs
        ! wc(:,:,:,:,2)    HG    HGH     wcx wavelet coeffs
        ! wc(:,:,:,:,3)    GH    GHH     wcy wavelet coeffs
        ! wc(:,:,:,:,4)    GG    GGH     wcxy wavelet coeffs
        ! wc(:,:,:,:,5)          HHG     wcz wavelet coeffs
        ! wc(:,:,:,:,6)          HGG     wcxz wavelet coeffs
        ! wc(:,:,:,:,7)          GHG     wcyz wavelet coeffs
        ! wc(:,:,:,:,8)          GGG     wcxyz wavelet coeffs
        !
        real(kind=rk), dimension(1:,1:,1:,1:,1:), intent(inout) :: wc
        integer(kind=ik) :: nx, ny, nz, nc, g, Bs(1:3)

        nx = size(u, 1)
        ny = size(u, 2)
        nz = size(u, 3)
        nc = size(u, 4)
        g  = params%g
        Bs = params%bs

#ifdef DEV
        if (.not.areArraysSameSize(u, wc(:,:,:,:,1))) then
            call abort(27222119, "Allocated arrays are not compatible?! Time for a drink.")
        endif
#endif

        wc = 0.0_rk

        ! note that what we call "Mallat ordering" here is in fact the "inflated" Mallat
        ! in the sense that Nx*Ny data gives 4 * Nx*Ny decomposition.

        ! copy from Spaghetti to Mallat ordering
        if (modulo(g, 2) == 0) then
            ! even g
            if (params%dim == 2) then
                wc( 1:nx:2, 1:ny:2, :, :, 1) = u(1:nx:2, 1:ny:2, 1:nz:2, :)
                wc( 1:nx:2, 1:ny:2, :, :, 2) = u(2:nx:2, 1:ny:2, 1:nz:2, :)
                wc( 1:nx:2, 1:ny:2, :, :, 3) = u(1:nx:2, 2:ny:2, 1:nz:2, :)
                wc( 1:nx:2, 1:ny:2, :, :, 4) = u(2:nx:2, 2:ny:2, 1:nz:2, :)
            else
                wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 1) = u(1:nx:2, 1:ny:2, 1:nz:2, :)
                wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 2) = u(2:nx:2, 1:ny:2, 1:nz:2, :)
                wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 3) = u(1:nx:2, 2:ny:2, 1:nz:2, :)
                wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 4) = u(2:nx:2, 2:ny:2, 1:nz:2, :)

                wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 5) = u(1:nx:2, 1:ny:2, 2:nz:2, :)
                wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 6) = u(2:nx:2, 1:ny:2, 2:nz:2, :)
                wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 7) = u(1:nx:2, 2:ny:2, 2:nz:2, :)
                wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 8) = u(2:nx:2, 2:ny:2, 2:nz:2, :)
            endif
        else
            ! odd g
            if (params%dim == 2) then
                wc( 2:nx-1:2, 2:ny-1:2, :, :, 1) = u(2:nx-1:2, 2:ny-1:2, :, :)
                wc( 2:nx-1:2, 2:ny-1:2, :, :, 2) = u(3:nx:2  , 2:ny-1:2  , :, :)
                wc( 2:nx-1:2, 2:ny-1:2, :, :, 3) = u(2:nx-1:2, 3:ny:2  , :, :)
                wc( 2:nx-1:2, 2:ny-1:2, :, :, 4) = u(3:nx:2  , 3:ny:2    , :, :)
            else
                wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 1) = u(2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :)
                wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 2) = u(3:nx:2  , 2:ny-1:2, 2:nz-1:2, :)
                wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 3) = u(2:nx-1:2, 3:ny:2  , 2:nz-1:2, :)
                wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 4) = u(3:nx:2  , 3:ny:2  , 2:nz-1:2, :)

                wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 5) = u(2:nx-1:2, 2:ny-1:2, 3:nz:2, :)
                wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 6) = u(3:nx:2  , 2:ny-1:2, 3:nz:2, :)
                wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 7) = u(2:nx-1:2, 3:ny:2  , 3:nz:2, :)
                wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 8) = u(3:nx:2  , 3:ny:2  , 3:nz:2, :)
            endif
        endif
    end subroutine



    subroutine mallat2spaghetti_block(params, wc, u)
        implicit none
        type (type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u
        ! The WC array contains SC (scaling function coeffs) as well as all WC (wavelet coeffs)
        ! Note: the precise naming of SC/WC is not really important. we just apply
        ! the correct decomposition/reconstruction filters - thats it.
        !
        ! INDEX            2D     3D     LABEL
        ! -----            --    ---     ---------------------------------
        ! wc(:,:,:,:,1)    HH    HHH     sc scaling function coeffs
        ! wc(:,:,:,:,2)    HG    HGH     wcx wavelet coeffs
        ! wc(:,:,:,:,3)    GH    GHH     wcy wavelet coeffs
        ! wc(:,:,:,:,4)    GG    GGH     wcxy wavelet coeffs
        ! wc(:,:,:,:,5)          HHG     wcz wavelet coeffs
        ! wc(:,:,:,:,6)          HGG     wcxz wavelet coeffs
        ! wc(:,:,:,:,7)          GHG     wcyz wavelet coeffs
        ! wc(:,:,:,:,8)          GGG     wcxyz wavelet coeffs
        !
        real(kind=rk), dimension(1:,1:,1:,1:,1:), intent(inout) :: wc
        integer(kind=ik) :: nx, ny, nz, nc, g, Bs(1:3)

        nx = size(u, 1)
        ny = size(u, 2)
        nz = size(u, 3)
        nc = size(u, 4)
        g  = params%g
        Bs = params%bs

#ifdef DEV
        if (.not.areArraysSameSize(u, wc(:,:,:,:,1))) then
            call abort(27222119, "Allocated arrays are not compatible?! Time for a drink. You look handsome today.")
        endif
#endif

        if (modulo(g, 2) == 0) then
            ! even g
            u(1:nx:2, 1:ny:2, :, :) = wc( 1:nx:2, 1:ny:2, :, :, 1)
            u(2:nx:2, 1:ny:2, :, :) = wc( 1:nx:2, 1:ny:2, :, :, 2)
            u(1:nx:2, 2:ny:2, :, :) = wc( 1:nx:2, 1:ny:2, :, :, 3)
            u(2:nx:2, 2:ny:2, :, :) = wc( 1:nx:2, 1:ny:2, :, :, 4)
        else
            ! odd g
            u(2:nx-1:2, 2:ny-1:2, :, :) = wc( 2:nx-1:2, 2:ny-1:2, :, :, 1)
            u(3:nx:2, 2:ny-1:2  , :, :) = wc( 2:nx-1:2, 2:ny-1:2, :, :, 2)
            u(2:nx-1:2, 3:ny:2  , :, :) = wc( 2:nx-1:2, 2:ny-1:2, :, :, 3)
            u(3:nx:2, 3:ny:2    , :, :) = wc( 2:nx-1:2, 2:ny-1:2, :, :, 4)
        endif

        ! copy from Spaghetti to Mallat ordering
        if (modulo(g, 2) == 0) then
            ! even g
            if (params%dim == 2) then
                u(1:nx:2, 1:ny:2, 1:nz:2, :) = wc( 1:nx:2, 1:ny:2, :, :, 1)
                u(2:nx:2, 1:ny:2, 1:nz:2, :) = wc( 1:nx:2, 1:ny:2, :, :, 2)
                u(1:nx:2, 2:ny:2, 1:nz:2, :) = wc( 1:nx:2, 1:ny:2, :, :, 3)
                u(2:nx:2, 2:ny:2, 1:nz:2, :) = wc( 1:nx:2, 1:ny:2, :, :, 4)
            else
                u(1:nx:2, 1:ny:2, 1:nz:2, :) = wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 1)
                u(2:nx:2, 1:ny:2, 1:nz:2, :) = wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 2)
                u(1:nx:2, 2:ny:2, 1:nz:2, :) = wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 3)
                u(2:nx:2, 2:ny:2, 1:nz:2, :) = wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 4)

                u(1:nx:2, 1:ny:2, 2:nz:2, :) = wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 5)
                u(2:nx:2, 1:ny:2, 2:nz:2, :) = wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 6)
                u(1:nx:2, 2:ny:2, 2:nz:2, :) = wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 7)
                u(2:nx:2, 2:ny:2, 2:nz:2, :) = wc( 1:nx:2, 1:ny:2, 1:nz:2, :, 8)
            endif
        else
            ! odd g
            if (params%dim == 2) then
                u(2:nx-1:2, 2:ny-1:2, :, :) = wc( 2:nx-1:2, 2:ny-1:2, :, :, 1)
                u(3:nx:2  , 2:ny-1:2  , :, :) = wc( 2:nx-1:2, 2:ny-1:2, :, :, 2)
                u(2:nx-1:2, 3:ny:2  , :, :) = wc( 2:nx-1:2, 2:ny-1:2, :, :, 3)
                u(3:nx:2  , 3:ny:2    , :, :) = wc( 2:nx-1:2, 2:ny-1:2, :, :, 4)
            else
                u(2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :) = wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 1)
                u(3:nx:2  , 2:ny-1:2, 2:nz-1:2, :) = wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 2)
                u(2:nx-1:2, 3:ny:2  , 2:nz-1:2, :) = wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 3)
                u(3:nx:2  , 3:ny:2  , 2:nz-1:2, :) = wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 4)

                u(2:nx-1:2, 2:ny-1:2, 3:nz:2, :) = wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 5)
                u(3:nx:2  , 2:ny-1:2, 3:nz:2, :) = wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 6)
                u(2:nx-1:2, 3:ny:2  , 3:nz:2, :) = wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 7)
                u(3:nx:2  , 3:ny:2  , 3:nz:2, :) = wc( 2:nx-1:2, 2:ny-1:2, 2:nz-1:2, :, 8)
            endif
        endif

    end subroutine


    ! manipulate wavelet coefficients in a neighborhood direction: applied
    ! if we find a coarser neighbor in this direction (coarse extension)
    subroutine coarseExtensionManipulateWC_block(params, wc, neighborhood)
        implicit none

        type (type_params), intent(in) :: params
        ! The WC array contains SC (scaling function coeffs) as well as all WC (wavelet coeffs)
        ! Note: the precise naming of SC/WC is not really important. we just apply
        ! the correct decomposition/reconstruction filters - thats it.
        !
        ! INDEX            2D     3D     LABEL
        ! -----            --    ---     ---------------------------------
        ! wc(:,:,:,:,1)    HH    HHH     sc scaling function coeffs
        ! wc(:,:,:,:,2)    HG    HGH     wcx wavelet coeffs
        ! wc(:,:,:,:,3)    GH    GHH     wcy wavelet coeffs
        ! wc(:,:,:,:,4)    GG    GGH     wcxy wavelet coeffs
        ! wc(:,:,:,:,5)          HHG     wcz wavelet coeffs
        ! wc(:,:,:,:,6)          HGG     wcxz wavelet coeffs
        ! wc(:,:,:,:,7)          GHG     wcyz wavelet coeffs
        ! wc(:,:,:,:,8)          GGG     wcxyz wavelet coeffs
        !
        real(kind=rk), dimension(1:,1:,1:,1:,1:), intent(inout) :: wc
        integer(kind=ik), intent(in) :: neighborhood

        integer(kind=ik) :: Nwcl, Nwcr, Nscl, Nscr, Nreconl, Nreconr
        integer(kind=ik) :: nx, ny, nz, nc, g, Bs(1:3), d

        nx = size(wc, 1)
        ny = size(wc, 2)
        nz = size(wc, 3)
        nc = size(wc, 4)
        g = params%g
        Bs = params%bs
        Nscl    = params%Nscl
        Nscr    = params%Nscr
        Nwcl    = params%Nwcl
        Nwcr    = params%Nwcr
        Nreconl = params%Nreconl
        Nreconr = params%Nreconr
        d       = 2_ik ** params%dim

        if (params%dim == 2) then
            ! 2D
            select case(neighborhood)
            case (9:10)
                ! FIXME to be modified for any other than CDF44
                ! NOTE: even though we set Nwcl=12 points to zero, this does not mean we
                ! kill 12 WC. They are on the extended grid, so effectively only 12/2
                ! are killed, many of which are in the ghost nodes layer
                ! -x
                wc(1:Nwcl, :, :, 1:nc, 2:d) = 0.0_rk
            case (15:16)
                ! -y
                wc(:, 1:Nwcl, :, 1:nc, 2:d) = 0.0_rk
            case (11:12)
                ! +x
                wc(nx-Nwcr:nx, :, :, 1:nc, 2:d) = 0.0_rk
            case (13:14)
                ! +y
                wc(:, ny-Nwcr:ny, :, 1:nc, 2:d) = 0.0_rk
            case(5)
                wc(1:Nwcl, ny-Nwcr:ny, :, 1:nc, 2:d) = 0.0_rk
            case(6)
                wc(1:Nwcl, 1:Nwcl, :, 1:nc, 2:d) = 0.0_rk
            case(7)
                wc(nx-Nwcr:nx, ny-Nwcr:ny, :, 1:nc, 2:d) = 0.0_rk
            case(8)
                wc(nx-Nwcr:nx, 1:Nwcl, :, 1:nc, 2:d) = 0.0_rk
            end select
        else
            ! 3D
            ! The finer neighbors are modified
            select case(neighborhood)
            ! ---faces---
            case (35:38)
                ! +x
                wc(nx-Nwcr:nx, :, :, 1:nc, 2:d) = 0.0_rk
            case (43:46)
                ! -x
                wc(1:Nwcl, :, :, 1:nc, 2:d) = 0.0_rk
            case (39:42)
                ! +y
                wc(:, ny-Nwcr:ny, :, 1:nc, 2:d) = 0.0_rk
            case (31:34)
                ! -y
                wc(:, 1:Nwcl, :, 1:nc, 2:d) = 0.0_rk
            case (27:30)
                ! +z
                wc(:, :, nz-Nwcr:nz, 1:nc, 2:d) = 0.0_rk
            case (47:50)
                ! -z
                wc(:, :, 1:Nwcl, 1:nc, 2:d) = 0.0_rk

            ! --- corners ---
            case (26)
                wc(1:Nwcl, 1:Nwcl, 1:Nwcl, 1:nc, 2:d) = 0.0_rk
            case (23)
                wc(nx-Nwcr:nx, 1:Nwcl, 1:Nwcl, 1:nc, 2:d) = 0.0_rk
            case (22)
                wc(1:Nwcl, 1:Nwcl, nz-Nwcr:nz, 1:nc, 2:d) = 0.0_rk
            case (19)
                wc(nx-Nwcr:nx, 1:Nwcl, nz-Nwcr:nz, 1:nc, 2:d) = 0.0_rk
            case (25)
                wc(1:Nwcl, ny-Nwcr:ny, 1:Nwcl, 1:nc, 2:d) = 0.0_rk
            case (21)
                wc(1:Nwcl, ny-Nwcr:ny, nz-Nwcr:nz, 1:nc, 2:d) = 0.0_rk
            case (20)
                wc(nx-Nwcr:nx, ny-Nwcr:ny, nz-Nwcr:nz, 1:nc, 2:d) = 0.0_rk
            case (24)
                wc(nx-Nwcr:nx, ny-Nwcr:ny, 1:Nwcl, 1:nc, 2:d) = 0.0_rk

            ! ---(partial) edges---
            case (51:52)
                wc(:, 1:Nwcl, nz-Nwcr:nz, 1:nc, 2:d) = 0.0_rk
            case (53:54)
                wc(nx-Nwcr:nx, :, nz-Nwcr:nz, 1:nc, 2:d) = 0.0_rk
            case (55:56)
                wc(:, ny-Nwcr:ny, nz-Nwcr:nz, 1:nc, 2:d) = 0.0_rk
            case (57:58)
                wc(1:Nwcl, :, nz-Nwcr:nz, 1:nc, 2:d) = 0.0_rk
            case (59:60)
                wc(:, 1:Nwcl, 1:Nwcl, 1:nc, 2:d) = 0.0_rk
            case (61:62)
                wc(nx-Nwcr:nx, :, 1:Nwcl, 1:nc, 2:d) = 0.0_rk
            case (63:64)
                wc(:, ny-Nwcr:ny, 1:Nwcl, 1:nc, 2:d) = 0.0_rk
            case (65:66)
                wc(1:Nwcl, :, 1:Nwcl, 1:nc, 2:d) = 0.0_rk
            case (67:68)
                wc(nx-Nwcr:nx, 1:Nwcl, :, 1:nc, 2:d) = 0.0_rk
            case (69:70)
                wc(1:Nwcl, 1:Nwcl, :, 1:nc, 2:d) = 0.0_rk
            case (71:72)
                wc(nx-Nwcr:nx, ny-Nwcr:ny, :, 1:nc, 2:d) = 0.0_rk
            case (73:74)
                wc(1:Nwcl, ny-Nwcr:ny, :, 1:nc, 2:d) = 0.0_rk

            end select

        endif
    end subroutine



    subroutine coarseExtensionManipulateSC_block(params, wc, u_copy, neighborhood)
        implicit none

        type (type_params), intent(in) :: params
        real(kind=rk), dimension(1:,1:,1:,1:), intent(inout) :: u_copy
        ! The WC array contains SC (scaling function coeffs) as well as all WC (wavelet coeffs)
        ! Note: the precise naming of SC/WC is not really important. we just apply
        ! the correct decomposition/reconstruction filters - thats it.
        !
        ! INDEX            2D     3D     LABEL
        ! -----            --    ---     ---------------------------------
        ! wc(:,:,:,:,1)    HH    HHH     sc scaling function coeffs
        ! wc(:,:,:,:,2)    HG    HGH     wcx wavelet coeffs
        ! wc(:,:,:,:,3)    GH    GHH     wcy wavelet coeffs
        ! wc(:,:,:,:,4)    GG    GGH     wcxy wavelet coeffs
        ! wc(:,:,:,:,5)          HHG     wcz wavelet coeffs
        ! wc(:,:,:,:,6)          HGG     wcxz wavelet coeffs
        ! wc(:,:,:,:,7)          GHG     wcyz wavelet coeffs
        ! wc(:,:,:,:,8)          GGG     wcxyz wavelet coeffs
        !
        real(kind=rk), dimension(1:,1:,1:,1:,1:), intent(inout) :: wc
        integer(kind=ik), intent(in) :: neighborhood

        integer(kind=ik) :: nx, ny, nz, nc, g, Bs(1:3)
        integer(kind=ik) :: Nscl, Nscr, Nreconl, Nreconr

        nx = size(wc, 1)
        ny = size(wc, 2)
        nz = size(wc, 3)
        nc = size(wc, 4)
        g = params%g
        Bs = params%bs
        Nscl    = params%Nscl
        Nscr    = params%Nscr
        Nreconl = params%Nreconl
        Nreconr = params%Nreconr


        if (params%dim == 2) then
            ! 2D
            select case(neighborhood)
            case (9:10)
                ! -x
                wc(1:Nscl, :, :, 1:nc, 1) = u_copy(1:Nscl, :, :, 1:nc)
            case (11:12)
                ! +x
                wc(nx-Nscr:nx, :, :, 1:nc, 1) = u_copy(nx-Nscr:nx, :, :, 1:nc)
            case (13:14)
                ! +y
                wc(:, ny-Nscr:ny, :, 1:nc, 1) = u_copy(:, ny-Nscr:ny, :, 1:nc)
            case (15:16)
                ! -y
                wc(:, 1:Nscl, :, 1:nc, 1) = u_copy(:, 1:Nscl, :, 1:nc)
            case(5)
                wc(1:Nscl, ny-Nscr:ny, :, 1:nc, 1) = u_copy(1:Nscl, ny-Nscr:ny, :, 1:nc)
            case(6)
                wc(1:Nscl, 1:Nscl, :, 1:nc, 1) = u_copy(1:Nscl, 1:Nscl, :, 1:nc)
            case(7)
                wc(nx-Nscr:nx, ny-Nscr:ny, :, 1:nc, 1) = u_copy(nx-Nscr:nx, ny-Nscr:ny, :, 1:nc)
            case(8)
                wc(nx-Nscr:nx, 1:Nscl, :, 1:nc, 1) = u_copy(nx-Nscr:nx, 1:Nscl, :, 1:nc)
            end select
        else
            ! 3D
            ! The finer neighbors are modified
            select case(neighborhood)
            ! ---faces---
            case (35:38)
                ! +x
                wc(nx-Nscr:nx, :, :, 1:nc, 1) = u_copy(nx-Nscr:nx, :, :, 1:nc)
            case (43:46)
                ! -x
                wc(1:Nscl, :, :, 1:nc, 1) = u_copy(1:Nscl, :, :, 1:nc)
            case (39:42)
                ! +y
                wc(:, ny-Nscr:ny, :, 1:nc, 1) = u_copy(:, ny-Nscr:ny, :, 1:nc)
            case (31:34)
                ! -y
                wc(:, 1:Nscl, :, 1:nc, 1) = u_copy(:, 1:Nscl, :, 1:nc)
            case (27:30)
                ! +z
                wc(:, :, nz-Nscr:nz, 1:nc, 1) = u_copy(:, :, nz-Nscr:nz, 1:nc)
            case (47:50)
                ! -z
                wc(:, :, 1:Nscl, 1:nc, 1) = u_copy(:, :, 1:Nscl, 1:nc)
            ! --- corners ---
            case (26)
                wc(1:Nscl, 1:Nscl, 1:Nscl, 1:nc, 1) = u_copy(1:Nscl, 1:Nscl, 1:Nscl, 1:nc)
            case (23)
                wc(nx-Nscr:nx, 1:Nscl, 1:Nscl, 1:nc, 1) = u_copy(nx-Nscr:nx, 1:Nscl, 1:Nscl, 1:nc)
            case (22)
                wc(1:Nscl, 1:Nscl, nz-Nscr:nz, 1:nc, 1) = u_copy(1:Nscl, 1:Nscl, nz-Nscr:nz, 1:nc)
            case (19)
                wc(nx-Nscr:nx, 1:Nscl, nz-Nscr:nz, 1:nc, 1) = u_copy(nx-Nscr:nx, 1:Nscl, nz-Nscr:nz, 1:nc)
            case (25)
                wc(1:Nscl, ny-Nscr:ny, 1:Nscl, 1:nc, 1) = u_copy(1:Nscl, ny-Nscr:ny, 1:Nscl, 1:nc)
            case (21)
                wc(1:Nscl, ny-Nscr:ny, nz-Nscr:nz, 1:nc, 1) = u_copy(1:Nscl, ny-Nscr:ny, nz-Nscr:nz, 1:nc)
            case (20)
                wc(nx-Nscr:nx, ny-Nscr:ny, nz-Nscr:nz, 1:nc, 1) = u_copy(nx-Nscr:nx, ny-Nscr:ny, nz-Nscr:nz, 1:nc)
            case (24)
                wc(nx-Nscr:nx, ny-Nscr:ny, 1:Nscl, 1:nc, 1) = u_copy(nx-Nscr:nx, ny-Nscr:ny, 1:Nscl, 1:nc)
            ! ---(partial) edges---
            case (51:52)
                wc(:, 1:Nscl, nz-Nscr:nz, 1:nc, 1) = u_copy(:, 1:Nscl, nz-Nscr:nz, 1:nc)
            case (53:54)
                wc(nx-Nscr:nx, :, nz-Nscr:nz, 1:nc, 1) = u_copy(nx-Nscr:nx, :, nz-Nscr:nz, 1:nc)
            case (55:56)
                wc(:, ny-Nscr:ny, nz-Nscr:nz, 1:nc, 1) = u_copy(:, ny-Nscr:ny, nz-Nscr:nz, 1:nc)
            case (57:58)
                wc(1:Nscl, :, nz-Nscr:nz, 1:nc, 1) = u_copy(1:Nscl, :, nz-Nscr:nz, 1:nc)
            case (59:60)
                wc(:, 1:Nscl, 1:Nscl, 1:nc, 1) = u_copy(:, 1:Nscl, 1:Nscl, 1:nc)
            case (61:62)
                wc(nx-Nscr:nx, :, 1:Nscl, 1:nc, 1) = u_copy(nx-Nscr:nx, :, 1:Nscl, 1:nc)
            case (63:64)
                wc(:, ny-Nscr:ny, 1:Nscl, 1:nc, 1) = u_copy(:, ny-Nscr:ny, 1:Nscl, 1:nc)
            case (65:66)
                wc(1:Nscl, :, 1:Nscl, 1:nc, 1) = u_copy(1:Nscl, :, 1:Nscl, 1:nc)
            case (67:68)
                wc(nx-Nscr:nx, 1:Nscl, :, 1:nc, 1) = u_copy(nx-Nscr:nx, 1:Nscl, :, 1:nc)
            case (69:70)
                wc(1:Nscl, 1:Nscl, :, 1:nc, 1) = u_copy(1:Nscl, 1:Nscl, :, 1:nc)
            case (71:72)
                wc(nx-Nscr:nx, ny-Nscr:ny, :, 1:nc, 1) = u_copy(nx-Nscr:nx, ny-Nscr:ny, :, 1:nc)
            case (73:74)
                wc(1:Nscl, ny-Nscr:ny, :, 1:nc, 1) = u_copy(1:Nscl, ny-Nscr:ny, :, 1:nc)
            end select

        endif

    end subroutine


    subroutine setup_wavelet(params)
        implicit none
        type (type_params), intent(inout) :: params

        if (allocated(params%GR)) deallocate(params%HD)
        if (allocated(params%GD)) deallocate(params%GD)
        if (allocated(params%HR)) deallocate(params%HR)
        if (allocated(params%GR)) deallocate(params%GR)

        ! for non-lifted wavelets: (Donoho wavelets)
        params%Nscl = 0
        params%Nscr = 0
        params%Nwcl = 0
        params%Nwcr = 0
        params%Nreconl = 0
        params%Nreconr = 0

        ! the wavelet filter banks:
        ! HD - low pass decomposition filter, H_TILDE
        ! GD - high pass decomposition filter, G_TILDE
        ! HR - low pass reconstruction filter, H
        ! GR - high pass reconstruction filter, G
        select case(params%wavelet)
        case("CDF44")
            ! H TILDE filter
            allocate( params%HD(-6:6) )
            params%HD = (/ -2.0_rk**(-9.0_rk), 0.0_rk,  9.0_rk*2.0_rk**(-8.0_rk), -2.0_rk**(-5.0_rk),  -63.0_rk*2.0_rk**(-9.0_rk),  9.0_rk*2.0_rk**(-5.0_rk), &
            87.0_rk*2.0_rk**(-7.0_rk), &
            9.0_rk*2.0_rk**(-5.0_rk), -63.0_rk*2.0_rk**(-9.0_rk), -2.0_rk**(-5.0_rk), 9.0_rk*2.0_rk**(-8.0_rk), 0.0_rk, -2.0_rk**(-9.0_rk)/)

            ! G TILDE filter
            allocate( params%GD(-2:4) )
            params%GD = (/ 1.0_rk/16.0_rk, 0.0_rk, -9.0_rk/16.0_rk, 1.0_rk, -9.0_rk/16.0_rk, 0.0_rk, 1.0_rk/16.0_rk  /)

            ! H filter
            allocate( params%HR(-3:3) )
            params%HR = (/ -1.0_rk/16.0_rk, 0.0_rk, 9.0_rk/16.0_rk, 1.0_rk, 9.0_rk/16.0_rk, 0.0_rk, -1.0_rk/16.0_rk  /)

            ! G filter
            allocate( params%GR(-7:5) )
            params%GR = (/ -2.0_rk**(-9.0_rk), 0.0_rk,  9.0_rk*2.0_rk**(-8.0_rk), +2.0_rk**(-5.0_rk),  -63.0_rk*2.0_rk**(-9.0_rk),  -9.0_rk*2.0_rk**(-5.0_rk), &
            87.0_rk*2.0_rk**(-7.0_rk), &
            -9.0_rk*2.0_rk**(-5.0_rk), -63.0_rk*2.0_rk**(-9.0_rk), 2.0_rk**(-5.0_rk), 9.0_rk*2.0_rk**(-8.0_rk), 0.0_rk, -2.0_rk**(-9.0_rk)/)

            params%order_predictor = "multiresolution_4th"

            ! NOTE: there is a story with even and odd numbers here. Simply, every 2nd
            ! value of SC/WC is zero anyways (in the reconstruction, see also setRequiredZerosWCSC_block)
            ! So for example deleting g+5 and g+6 does not make any difference, because the 6th is zero anyways
            ! scaling function coeffs to be copied:
            params%Nscl = params%g+5 ! dictated by support of h_tilde (HD) filter for SC
            params%Nscr = params%g+5
            ! wavelet coefficients to be deleted:
            params%Nwcl = params%Nscl+3 ! chosen such that g_tilde (GD) not not see the copied SC
            params%Nwcr = params%Nscr+5
            ! last reocnstructed point is the support of GR filter not seing any WC set to zero anymore
            params%Nreconl = params%Nwcl+7 ! support of GR -7:5
            params%Nreconr = params%Nwcr+5

            if (params%g<7) then
                write(*,*) trim(adjustl(params%wavelet)), " g=", params%g
                call abort(88888881, "The selected wavelet requires at least g=7 ghost nodes.")
            endif

        case ("CDF42")
            ! H TILDE filter
            allocate( params%HD(-4:4) )
            params%HD = (/ 2.0_rk**(-6.0_rk), 0.0_rk, -2.0_rk**(-3.0_rk), 2.0_rk**(-2.0_rk), 23.0_rk*2**(-5.0_rk), 2.0_rk**(-2.0_rk), -2.0_rk**(-3.0_rk), 0.0_rk, 2.0_rk**(-6.0_rk) /)

            ! G TILDE filter
            allocate( params%GD(-2:4) )
            params%GD = (/ 1.0_rk/16.0_rk, 0.0_rk, -9.0_rk/16.0_rk, 1.0_rk, -9.0_rk/16.0_rk, 0.0_rk, 1.0_rk/16.0_rk  /)

            ! H filter
            allocate( params%HR(-3:3) )
            params%HR = (/ -1.0_rk/16.0_rk, 0.0_rk, 9.0_rk/16.0_rk, 1.0_rk, 9.0_rk/16.0_rk, 0.0_rk, -1.0_rk/16.0_rk  /)

            ! G filter
            allocate( params%GR(-5:3) )
            params%GR = (/ 2.0_rk**(-6.0_rk), -0.0_rk, -2.0_rk**(-3.0_rk), -2.0_rk**(-2.0_rk), +23.0_rk*2**(-5.0_rk), -2.0_rk**(-2.0_rk), -2.0_rk**(-3.0_rk), -0.0_rk, 2.0_rk**(-6.0_rk) /)

            params%order_predictor = "multiresolution_4th"

            params%Nscl = params%g+3
            params%Nscr = params%g+3
            params%Nwcl = params%Nscl+3 ! chosen such that g_tilde (GD) not not see the copied SC
            params%Nwcr = params%Nscr+5
            params%Nreconl = params%Nwcl+5 ! support of GR -5:3
            params%Nreconr = params%Nwcr+3

            if (params%g<5) then
                write(*,*) trim(adjustl(params%wavelet)), " g=", params%g
                call abort(88888881, "The selected wavelet requires at least g=5 ghost nodes.")
            endif

        case ("CDF40")
            ! H TILDE filter
            allocate( params%HD(0:0) )
            params%HD = (/1.0_rk/)

            ! G TILDE filter
            allocate( params%GD(-2:4) )
            params%GD = (/ 1.0_rk/16.0_rk, 0.0_rk, -9.0_rk/16.0_rk, 1.0_rk, -9.0_rk/16.0_rk, 0.0_rk, 1.0_rk/16.0_rk  /)

            ! H filter
            allocate( params%HR(-3:3) )
            params%HR = (/ -1.0_rk/16.0_rk, 0.0_rk, 9.0_rk/16.0_rk, 1.0_rk, 9.0_rk/16.0_rk, 0.0_rk, -1.0_rk/16.0_rk  /)

            ! G filter
            allocate( params%GR(-2:0) )
            params%GR = (/ 0.0_rk, 1.0_rk, 0.0_rk /)

            params%order_predictor = "multiresolution_4th"

            if (params%g<4) then
                write(*,*) trim(adjustl(params%wavelet)), " g=", params%g
                call abort(88888881, "The selected wavelet requires at least g=4 ghost nodes.")
            endif

        case ("CDF20")
            ! H TILDE filter
            allocate( params%HD(0:0) )
            params%HD = (/1.0_rk/)

            ! G TILDE filter
            allocate( params%GD(0:2) )
            params%GD = (/ -0.5_rk, 1.0_rk, -0.5_rk  /)

            ! H filter
            allocate( params%HR(-1:1) )
            params%HR = (/ 0.5_rk, 1.0_rk, 0.5_rk  /)

            ! G filter
            allocate( params%GR(-2:0) )
            params%GR = (/ 0.0_rk, 1.0_rk, 0.0_rk /)

            params%order_predictor = "multiresolution_2nd"

            if (params%g<2) then
                write(*,*) trim(adjustl(params%wavelet)), " g=", params%g
                call abort(88888881, "The selected wavelet requires at least g=2 ghost nodes.")
            endif

        case("CDF22")
            ! H TILDE filter
            allocate( params%HD(-2:2) )
            params%HD = (-1.0_rk)*(/+1.0_rk/8.0_rk, -1.0_rk/4.0_rk, -3.0_rk/4.0_rk, -1.0_rk/4.0_rk, +1.0_rk/8.0_rk/) ! H TILDE

            ! G TILDE filter
            allocate( params%GD(0:2) )
            params%GD = (/ -0.5_rk, 1.0_rk, -0.5_rk  /)

            ! H filter
            allocate( params%HR(-1:1) )
            params%HR = (/ 0.5_rk, 1.0_rk, 0.5_rk  /)

            ! G filter
            allocate( params%GR(-3:1) )
            params%GR = (-1.0_rk)*params%hd*(/-1.0_rk, 1.0_rk, -1.0_rk, 1.0_rk, -1.0_rk /)

            params%order_predictor = "multiresolution_2nd"

            params%Nscl = params%g+1
            params%Nscr = params%g+1
            params%Nwcl = params%Nscl + 0 ! chosen such that g_tilde (GD) not not see the copied SC
            params%Nwcr = params%Nscr + 2
            params%Nreconl = params%Nwcl+3 ! support of GR -3:1
            params%Nreconr = params%Nwcr+1

            if (params%g<3) then
                write(*,*) trim(adjustl(params%wavelet)), " g=", params%g
                call abort(88888881, "The selected wavelet requires at least g=3 ghost nodes.")
            endif

        case default
            call abort( 3006221, "Unkown biorothonal wavelet specified. Set course for adventure! params%wavelet="//trim(adjustl(params%wavelet)) )

        end select

        if (params%rank==0) then
            write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            write(*,*) "                      Wavelet-setup"
            write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
            write(*,*) "The wavelet is ", trim(adjustl(params%wavelet))
            write(*,*) "During coarse extension, we will copy SC:", params%Nscl, params%Nscr
            write(*,*) "During coarse extension, we will delete WC:", params%Nwcl, params%Nwcr
            write(*,*) "During coarse extension, we will reconstruct u:", params%Nreconl, params%Nreconr
            write(*,*) "The predictor is: ", trim(adjustl(params%order_predictor))
            write(*,'(A,"[",i2,":",i1,"]=",14(es12.4,1x))') "HD", lbound(params%HD, dim=1), ubound(params%HD, dim=1), params%HD
            write(*,'(A,"[",i2,":",i1,"]=",14(es12.4,1x))') "GD", lbound(params%GD, dim=1), ubound(params%GD, dim=1), params%GD
            write(*,'(A,"[",i2,":",i1,"]=",14(es12.4,1x))') "HR", lbound(params%HR, dim=1), ubound(params%HR, dim=1), params%HR
            write(*,'(A,"[",i2,":",i1,"]=",14(es12.4,1x))') "GR", lbound(params%GR, dim=1), ubound(params%GR, dim=1), params%GR
            write(*,*) "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
        endif

    end subroutine






    ! one-dimensional, periodized filter
    subroutine filter1P(params, u, u_filtered, filter, a1, b1)
        implicit none
        type (type_params), intent(in) :: params
        ! filter bound indices
        integer, intent(in) :: a1, b1
        ! the actual filter
        real(kind=rk), dimension(a1:b1), intent(in) :: filter
        ! the signal to be filtered
        real(kind=rk), dimension(1:), intent(in) :: u
        ! the resulting filtered signal
        real(kind=rk), dimension(1:), intent(inout) :: u_filtered

        integer(kind=ik) :: N, i, j

        N = size(u)
        u_filtered = 0.0_rk

        do i = 1, N
            do j = a1, b1
                u_filtered(i) = u_filtered(i) + u( perindex(i+j,N) ) * filter(j)
            enddo
        enddo

    end subroutine

    ! 1D filter excluding ghost nodes
    subroutine filter1G(params, u, u_filtered, filter, a1, b1)
        implicit none
        type (type_params), intent(in) :: params
        ! filter bound indices
        integer, intent(in) :: a1, b1
        ! the actual filter
        real(kind=rk), dimension(a1:b1), intent(in) :: filter
        ! the signal to be filtered
        real(kind=rk), dimension(1:), intent(in) :: u
        ! the resulting filtered signal
        real(kind=rk), dimension(1:), intent(inout) :: u_filtered

        integer(kind=ik) :: N, i, j

        N = size(u)
        u_filtered = 0.0_rk

        ! apply filter f to periodic signal u, i.e. convolute with filter
        do i =  params%g+1, N-params%g
            do j = a1, b1
                u_filtered(i) = u_filtered(i) + u(i+j) * filter(j)
            enddo
        enddo
    end subroutine

    subroutine dump_block(u, file)
        real(kind=rk), dimension(:, :, :, :), intent(in) :: u
        character(len=*) :: file
        integer :: ii
        write(*,*) "Dumping block to "//file
        open(unit=32, file=file, status="replace")
        do ii = 1, size(u,2)
        write(32,'(48(es12.4,";"))') u(:, ii, 1, 1)
        enddo
        close(32)
    end subroutine



    ! multi-dimensional FWT using 1D non-periodic filtering routines
    ! Inplace
    subroutine WaveDecomposition_dim1( params, u_wc )
        implicit none
        type (type_params), intent(in) :: params
        ! Input: data Output: FWT(DATA) in Spagghetti-ordering
        real(kind=rk), dimension(:, :, :, :), intent(inout) :: u_wc
        real(kind=rk), dimension(:, :, :, :), allocatable, save :: u_wc_copy
        real(kind=rk), dimension(:), allocatable, save :: buffer1, buffer2
        integer(kind=ik) :: ix, iy, iz, ic, g, Bs(1:3), nx, ny, nz, nc
        nx = size(u_wc, 1)
        ny = size(u_wc, 2)
        nz = size(u_wc, 3)
        nc = size(u_wc, 4)
        g  = params%g
        Bs = params%Bs

        if (allocated(u_wc_copy)) then
            if (.not.areArraysSameSize(u_wc_copy, u_wc)) deallocate(u_wc_copy)
        endif
        if (.not. allocated(u_wc_copy)) allocate(u_wc_copy(1:nx,1:ny,1:nz,1:nc))
        if (.not. allocated(params%HD)) call abort(1717229, "Wavelet setup not called?!")
        if (.not. allocated(params%GD)) call abort(1717231, "Wavelet setup not called?!")

        do ic = 1, nc
            ! ~~~~~~~~~~~~~~~~~~~~~~ X ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            if (allocated(buffer1)) then
                if (size(buffer1, dim=1)/=nx) deallocate(buffer1)
            endif
            if (.not.allocated(buffer1)) allocate(buffer1(1:nx))
            if (allocated(buffer2)) then
                if (size(buffer2, dim=1)/=nx) deallocate(buffer2)
            endif
            if (.not.allocated(buffer2)) allocate(buffer2(1:nx))

            do iy = 1, ny
                do iz = 1, nz
                    ! low-pass filter (scaling function)
                    call filter1G(params, u_wc(:,iy,iz,ic), buffer1, params%HD, lbound(params%HD,dim=1), ubound(params%HD,dim=1))

                    ! high-pass filter (these guys are the details)
                    call filter1G(params, u_wc(:,iy,iz,ic), buffer2, params%GD, lbound(params%GD,dim=1), ubound(params%GD,dim=1))

                    ! decimation by 2, sort into array
                    u_wc(1:Bs(1)/2,iy,iz,ic)       = buffer1( (g+1):(Bs(1)+g):2 )
                    u_wc(Bs(1)/2+1:Bs(1),iy,iz,ic) = buffer2( (g+1):(Bs(1)+g):2 )
                enddo
            enddo

            ! ~~~~~~~~~~~~~~~~~~~~~~ Y ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            if (allocated(buffer1)) then
                if (size(buffer1, dim=1)/=ny) deallocate(buffer1)
            endif
            if (.not.allocated(buffer1)) allocate(buffer1(1:ny))
            if (allocated(buffer2)) then
                if (size(buffer2, dim=1)/=ny) deallocate(buffer2)
            endif
            if (.not.allocated(buffer2)) allocate(buffer2(1:ny))

            do ix = 1, nx
                do iz = 1, nz
                    ! low-pass filter (scaling function)
                    call filter1G(params, u_wc(ix,:,iz,ic), buffer1, params%HD, lbound(params%HD,dim=1), ubound(params%HD,dim=1))

                    ! high-pass filter (these guys are the details)
                    call filter1G(params, u_wc(ix,:,iz,ic), buffer2, params%GD, lbound(params%GD,dim=1), ubound(params%GD,dim=1))

                    ! decimation by 2, sort into array
                    u_wc(ix,1:Bs(2)/2,iz,ic)       = buffer1( (g+1):(Bs(2)+g):2 )
                    u_wc(ix,Bs(2)/2+1:Bs(2),iz,ic) = buffer2( (g+1):(Bs(2)+g):2 )
                enddo
            enddo

            ! ~~~~~~~~~~~~~~~~~~~~~~ Z ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
            if (nz==1) cycle

            if (allocated(buffer1)) then
                if (size(buffer1, dim=1)/=nz) deallocate(buffer1)
            endif
            if (.not.allocated(buffer1)) allocate(buffer1(1:nz))
            if (allocated(buffer2)) then
                if (size(buffer2, dim=1)/=nz) deallocate(buffer2)
            endif
            if (.not.allocated(buffer2)) allocate(buffer2(1:nz))

            do ix = 1, nx
                do iy = 1, ny
                    ! low-pass filter (scaling function)
                    call filter1G(params, u_wc(ix,iy,:,ic), buffer1, params%HD, lbound(params%HD,dim=1), ubound(params%HD,dim=1))

                    ! high-pass filter (these guys are the details)
                    call filter1G(params, u_wc(ix,iy,:,ic), buffer2, params%GD, lbound(params%GD,dim=1), ubound(params%GD,dim=1))

                    ! decimation by 2, sort into array
                    u_wc(ix,iy,1:Bs(3)/2,ic)       = buffer1( (g+1):(Bs(3)+g):2 )
                    u_wc(ix,iy,Bs(3)/2+1:Bs(3),ic) = buffer2( (g+1):(Bs(3)+g):2 )
                enddo
            enddo
        enddo ! loop over components

        ! coefficients are now in compressed Mallat ordering, ie for u_wc:
        !
        ! hh hh hh hh hg hg hg hg ** ** **
        ! hh hh hh hh hg hg hg hg ** ** **
        ! hh hh hh hh hg hg hg hg ** ** **
        ! hh hh hh hh hg hg hg hg ** ** **
        ! gh gh gh gh gg gg gg gg ** ** **
        ! gh gh gh gh gg gg gg gg ** ** **
        ! gh gh gh gh gg gg gg gg ** ** **
        ! gh gh gh gh gg gg gg gg ** ** **
        ! ** ** ** ** ** ** ** ** ** ** **
        ! ** ** ** ** ** ** ** ** ** ** **
        ! ** ** ** ** ** ** ** ** ** ** **
        !
        ! Note ** marks coefficients that could not be computed (in the ghost nodes layer)
        ! compressed Mallat means the valid coeffs run 1:Bs and NOT 1:Bs+2*g
        u_wc_copy = u_wc

        if (params%dim==2) then
            ! copy to the back spaghetti-ordered coefficients to the block
            u_wc( (g+1):(Bs(1)+g):2, (g+1):(Bs(2)+g):2, :, :) = u_wc_copy(1:Bs(1)/2, 1:Bs(2)/2, :, :)
            u_wc( (g+2):(Bs(1)+g):2, (g+1):(Bs(2)+g):2, :, :) = u_wc_copy(1:Bs(1)/2, Bs(2)/2+1:Bs(2), :, :)
            u_wc( (g+1):(Bs(1)+g):2, (g+2):(Bs(2)+g):2, :, :) = u_wc_copy(Bs(1)/2+1:Bs(1), 1:Bs(2)/2, :, :)
            u_wc( (g+2):(Bs(1)+g):2, (g+2):(Bs(2)+g):2, :, :) = u_wc_copy(Bs(1)/2+1:Bs(1), Bs(2)/2+1:Bs(2), :, :)
        else
            ! copy to the back spaghetti-ordered coefficients to the block
            u_wc( (g+1):(Bs(1)+g):2, (g+1):(Bs(2)+g):2, (g+1):(Bs(3)+g):2, :) = u_wc_copy(1:Bs(1)/2, 1:Bs(2)/2, 1:Bs(3)/2, :)
            u_wc( (g+2):(Bs(1)+g):2, (g+1):(Bs(2)+g):2, (g+1):(Bs(3)+g):2, :) = u_wc_copy(1:Bs(1)/2, Bs(2)/2+1:Bs(2), 1:Bs(3)/2, :)
            u_wc( (g+1):(Bs(1)+g):2, (g+2):(Bs(2)+g):2, (g+1):(Bs(3)+g):2, :) = u_wc_copy(Bs(1)/2+1:Bs(1), 1:Bs(2)/2, 1:Bs(3)/2, :)
            u_wc( (g+2):(Bs(1)+g):2, (g+2):(Bs(2)+g):2, (g+1):(Bs(3)+g):2, :) = u_wc_copy(Bs(1)/2+1:Bs(1), Bs(2)/2+1:Bs(2), 1:Bs(3)/2, :)

            u_wc( (g+1):(Bs(1)+g):2, (g+1):(Bs(2)+g):2, (g+2):(Bs(3)+g):2, :) = u_wc_copy(1:Bs(1)/2, 1:Bs(2)/2, Bs(3)/2+1:Bs(3), :)
            u_wc( (g+2):(Bs(1)+g):2, (g+1):(Bs(2)+g):2, (g+2):(Bs(3)+g):2, :) = u_wc_copy(1:Bs(1)/2, Bs(2)/2+1:Bs(2), Bs(3)/2+1:Bs(3), :)
            u_wc( (g+1):(Bs(1)+g):2, (g+2):(Bs(2)+g):2, (g+2):(Bs(3)+g):2, :) = u_wc_copy(Bs(1)/2+1:Bs(1), 1:Bs(2)/2, Bs(3)/2+1:Bs(3), :)
            u_wc( (g+2):(Bs(1)+g):2, (g+2):(Bs(2)+g):2, (g+2):(Bs(3)+g):2, :) = u_wc_copy(Bs(1)/2+1:Bs(1), Bs(2)/2+1:Bs(2), Bs(3)/2+1:Bs(3), :)
        endif
    end subroutine


    !-----------------------------------------------------------------------------
    ! Reconstruction from low- and high pass filtered coefficients.
    ! Data is first upsampled, then filtered with the reconstruction filters.
    ! Note reconstruction filters are reverse of decomposition filters.
    !
    ! Input: hh hg hh hg hh hg hh hg
    !        gh gg gh gg gh gg gh gg
    !        hh hg hh hg hh hg hh hg
    !        gh gg gh gg gh gg gh gg
    !        hh hg hh hg hh hg hh hg
    !        gh gg gh gg gh gg gh gg
    ! Note: in input in spaghetti ordering is synced
    !-----------------------------------------------------------------------------
    subroutine WaveReconstruction_dim1( params, u_wc )
        implicit none
        type (type_params), intent(in) :: params
        real(kind=rk), dimension(:, :, :, :), intent(inout) :: u_wc
        real(kind=rk), dimension(:), allocatable, save :: buffer1, buffer2, buffer3
        real(kind=rk), allocatable, save :: u_wc_tmp(:,:,:,:)
        integer(kind=ik) :: ix, iy, iz, ic, g, Bs(1:3), nx, ny, nz, nc, n(1:3), ii
        integer(kind=ik) :: jx, jy, jz
        nx = size(u_wc, 1)
        ny = size(u_wc, 2)
        nz = size(u_wc, 3)
        nc = size(u_wc, 4)
        g  = params%g
        Bs = params%Bs
        n  = (params%Bs+2*g) / 2


        if (allocated(u_wc_tmp)) then
            if (.not. areArraysSameSize(u_wc, u_wc_tmp)) deallocate(u_wc_tmp)
        endif
        if (.not. allocated(u_wc_tmp)) then
            allocate (u_wc_tmp(size(u_wc,1), size(u_wc,2), size(u_wc,3), size(u_wc,4)))
        endif
        if (.not. allocated(params%HD)) call abort(1717229, "Wavelet setup not called?!")
        if (.not. allocated(params%GD)) call abort(1717231, "Wavelet setup not called?!")

        ! Input is (synchronized, ie with ghost nodes) spaghetti ordering
        ! re-arrange to (synchronized) Mallat ordering
        if (modulo(g,2)==0) then
            ! even: 1st point (in u_wc, spaghetti order) is SC
            if (params%dim==2) then
                u_wc_tmp( 1:n(1), 1:n(2)              , :, :) = u_wc(1:Bs(1)+2*g-1:2 , 1:Bs(1)+2*g-1:2, :, :)
                u_wc_tmp( n(1)+1:2*n(1), 1:n(2)       , :, :) = u_wc(1:Bs(1)+2*g-1:2 , 2:Bs(2)+2*g:2, :, :)
                u_wc_tmp( 1:n(1), n(2)+1:2*n(2)       , :, :) = u_wc(2:Bs(1)+2*g:2   , 1:Bs(2)+2*g-1:2, :, :)
                u_wc_tmp( n(1)+1:2*n(1), n(2)+1:2*n(2), :, :) = u_wc(2:Bs(1)+2*g:2   , 2:Bs(2)+2*g:2, :, :)
            else

                ! do jz = 1, nz !jx,jy,jz loop over the "fine" grid SC/WC in spaghetti-order)
                !     do jy = 1, ny
                !         do jx = 1, nx
                !             ix = jx - (g+1) ! the first point is (0,0,0) (and SC coeff)
                !             iy = jy - (g+1)
                !             iz = jz - (g+1)
                !
                !             if ((modulo(ix,2)==0) .and. (modulo(iy,2)==0) .and. (modulo(iz,2)==0)) then
                !                 ! SC
                !
                !             elseif ((modulo(ix,2)==0) .and. (modulo(iy,2)==0) .and. (modulo(iz,2)==0)) then
                !             endif
                !         enddo
                !         enddo
                !         enddo


                u_wc_tmp( 1:n(1), 1:n(2), 1:n(3), :) = u_wc(1:Bs(1)+2*g-1:2 , 1:Bs(2)+2*g-1:2, 1:Bs(3)+2*g-1:2, :)
                u_wc_tmp( n(1)+1:2*n(1), 1:n(2), 1:n(3), :) = u_wc(1:Bs(1)+2*g-1:2 , 2:Bs(2)+2*g:2, 1:Bs(3)+2*g-1:2, :)
                u_wc_tmp( 1:n(1), n(2)+1:2*n(2), 1:n(3), :) = u_wc(2:Bs(1)+2*g:2   , 1:Bs(2)+2*g-1:2, 1:Bs(3)+2*g-1:2, :)
                u_wc_tmp( n(1)+1:2*n(1), n(2)+1:2*n(2), 1:n(3), :) = u_wc(2:Bs(1)+2*g:2   , 2:Bs(2)+2*g:2, 1:Bs(3)+2*g-1:2, :)

                u_wc_tmp( 1:n(1), 1:n(2), n(3)+1:2*n(3), :) = u_wc(1:Bs(1)+2*g-1:2 , 1:Bs(2)+2*g-1:2, 2:Bs(3)+2*g:2, :)
                u_wc_tmp( n(1)+1:2*n(1), 1:n(2), n(3)+1:2*n(3), :) = u_wc(1:Bs(1)+2*g-1:2 , 2:Bs(2)+2*g:2, 2:Bs(3)+2*g:2, :)
                u_wc_tmp( 1:n(1), n(2)+1:2*n(2), n(3)+1:2*n(3), :) = u_wc(2:Bs(1)+2*g:2   , 1:Bs(2)+2*g-1:2, 2:Bs(3)+2*g:2, :)
                u_wc_tmp( n(1)+1:2*n(1), n(2)+1:2*n(2), n(3)+1:2*n(3), :) = u_wc(2:Bs(1)+2*g:2   , 2:Bs(2)+2*g:2, 2:Bs(3)+2*g:2, :)
            endif

            if (allocated(buffer1)) then
                if (size(buffer1, dim=1)/=nx) deallocate(buffer1)
            endif
            if (.not.allocated(buffer1)) allocate(buffer1(1:nx))
            if (allocated(buffer2)) then
                if (size(buffer2, dim=1)/=nx) deallocate(buffer2)
            endif
            if (.not.allocated(buffer2)) allocate(buffer2(1:nx))
            if (allocated(buffer3)) then
                if (size(buffer3, dim=1)/=nx) deallocate(buffer3)
            endif
            if (.not.allocated(buffer3)) allocate(buffer3(1:nx))

            do ic = 1, nc
                do iy = 1, ny
                    do iz = 1, nz
                        ! fill upsampling buffer for low-pass filter: every second point
                        ! apply low-pass filter to upsampled signal
                        buffer3 = 0.0_rk
                        ! even g: 1st point is collocation point
                        buffer3(1:nx-1:2) = u_wc_tmp(1:n(1), iy, iz, ic) ! SC
                        call filter1G(params, buffer3, buffer1, params%HR, lbound(params%HR,dim=1), ubound(params%HR,dim=1))

                        ! fill upsampling buffer for high-pass filter: every second point
                        buffer3 = 0.0_rk
                        buffer3(1:nx-1:2) = u_wc_tmp(n(1)+1:2*n(1), iy, iz, ic) ! WC
                        call filter1G(params, buffer3, buffer2, params%GR, lbound(params%GR,dim=1), ubound(params%GR,dim=1))

                        u_wc(:, iy, iz, ic) = buffer1 + buffer2
                    enddo
                enddo
            enddo

            if (allocated(buffer1)) then
                if (size(buffer1, dim=1)/=ny) deallocate(buffer1)
            endif
            if (.not.allocated(buffer1)) allocate(buffer1(1:ny))
            if (allocated(buffer2)) then
                if (size(buffer2, dim=1)/=ny) deallocate(buffer2)
            endif
            if (.not.allocated(buffer2)) allocate(buffer2(1:ny))
            if (allocated(buffer3)) then
                if (size(buffer3, dim=1)/=ny) deallocate(buffer3)
            endif
            if (.not.allocated(buffer3)) allocate(buffer3(1:ny))

            do ic = 1, nc
                do ix = 1, nx
                    do iz = 1, nz
                        ! fill upsampling buffer for low-pass filter: every second point
                        ! apply low-pass filter to upsampled signal
                        buffer3 = 0.0_rk
                        buffer3(1:ny-1:2) = u_wc(ix, 1:n(2), iz, ic)
                        call filter1G(params, buffer3, buffer1, params%HR, lbound(params%HR,dim=1), ubound(params%HR,dim=1))

                        ! fill upsampling buffer for high-pass filter: every second point
                        buffer3 = 0.0_rk
                        buffer3(1:ny-1:2) = u_wc(ix, n(2)+1:2*n(2), iz, ic)
                        call filter1G(params, buffer3, buffer2, params%GR, lbound(params%GR,dim=1), ubound(params%GR,dim=1))

                        u_wc(ix, :, iz, ic) = buffer1 + buffer2
                    enddo
                enddo
            enddo

            !!!!!!!!!!!!!!!!!
            if (nz==1) return
            !!!!!!!!!!!!!!!!!

            if (allocated(buffer1)) then
                if (size(buffer1, dim=1)/=nz) deallocate(buffer1)
            endif
            if (.not.allocated(buffer1)) allocate(buffer1(1:nz))
            if (allocated(buffer2)) then
                if (size(buffer2, dim=1)/=nz) deallocate(buffer2)
            endif
            if (.not.allocated(buffer2)) allocate(buffer2(1:nz))
            if (allocated(buffer3)) then
                if (size(buffer3, dim=1)/=nz) deallocate(buffer3)
            endif
            if (.not.allocated(buffer3)) allocate(buffer3(1:nz))


            do ic = 1, nc
                do ix = 1, nx
                    do iy = 1, ny
                        ! fill upsampling buffer for low-pass filter: every second point
                        ! apply low-pass filter to upsampled signal
                        buffer3 = 0.0_rk
                        buffer3(1:nz-1:2) = u_wc(ix, iy, 1:n(2), ic)
                        call filter1G(params, buffer3, buffer1, params%HR, lbound(params%HR,dim=1), ubound(params%HR,dim=1))

                        ! fill upsampling buffer for high-pass filter: every second point
                        buffer3 = 0.0_rk
                        buffer3(1:nz-1:2) = u_wc(ix, iy, n(2)+1:2*n(2), ic)
                        call filter1G(params, buffer3, buffer2, params%GR, lbound(params%GR,dim=1), ubound(params%GR,dim=1))

                        u_wc(ix, iy, :, ic) = buffer1 + buffer2
                    enddo
                enddo
            enddo

        else
            ! odd: 1st point (in u_wc, spaghetti order) is WC
            ! NOTE: if g is odd, then there is a goofy shift in the coefficients: the
            ! spaghetti ordering is arranged like this:
            !
            ! SC WC SC WC
            ! WC WC WC WC
            ! SC WC SC WC
            ! WC WC WC WC
            !
            ! Thus, if g is odd, we do have the same number of coefficients for all of SC, WCx, WCy, WCxy
            ! but they are not symmetric: on the left and right block boundary their number differs.
            ! To correct for this shift we discard some coefficients (which is not a problem because not all
            ! filters have the same length, in particular they are not left/right symmetric anyways)
            u_wc_tmp = 0.0_rk

            if (params%dim == 2) then
                ! SC
                u_wc_tmp( 1:n(1)       , 1:n(2)       , :, :) = u_wc(2:Bs(1)+2*g  :2 , 2:Bs(2)+2*g:2, :, :)
                ! WCx
                u_wc_tmp( n(1)+1:2*n(1), 1:n(2)-1     , :, :) = u_wc(2:Bs(1)+2*g  :2 , 3:Bs(2)+2*g-1:2, :, :)
                ! WCy
                u_wc_tmp( 1:n(1)-1     , n(2)+1:2*n(2), :, :) = u_wc(3:Bs(1)+2*g-1:2 , 2:Bs(2)+2*g:2, :, :)
                ! WCxy
                u_wc_tmp( n(1)+1:2*n(1)-1, n(2)+1:2*n(2)-1, :, :) = u_wc(3:Bs(1)+2*g-1:2 , 3:Bs(2)+2*g-1:2, :, :)
            else
                ! SC
                u_wc_tmp( 1:n(1)       , 1:n(2)       , 1:n(3), :) = u_wc(2:Bs(1)+2*g  :2 , 2:Bs(2)+2*g:2, 2:Bs(3)+2*g:2, :)
                u_wc_tmp( n(1)+1:2*n(1), 1:n(2)-1       , 1:n(3), :) = u_wc(2:Bs(1)+2*g  :2 , 3:Bs(2)+2*g-1:2, 2:Bs(3)+2*g:2, :)
                u_wc_tmp( 1:n(1)-1     , n(2)+1:2*n(2), 1:n(3), :) = u_wc(3:Bs(1)+2*g-1:2 , 2:Bs(2)+2*g:2, 2:Bs(3)+2*g:2, :)
                u_wc_tmp( n(1)+1:2*n(1)-1, n(2)+1:2*n(2)-1, 1:n(3), :) = u_wc(3:Bs(1)+2*g-1:2 , 3:Bs(2)+2*g-1:2, 2:Bs(3)+2*g:2, :)

                u_wc_tmp( 1:n(1)       , 1:n(2)       , n(3)+1:2*n(3)-1, :) = u_wc(2:Bs(1)+2*g  :2 , 2:Bs(2)+2*g:2, 3:Bs(3)+2*g-1:2, :)
                u_wc_tmp( n(1)+1:2*n(1), 1:n(2)-1       , n(3)+1:2*n(3)-1, :) = u_wc(2:Bs(1)+2*g  :2 , 3:Bs(2)+2*g-1:2, 3:Bs(3)+2*g-1:2, :)
                u_wc_tmp( 1:n(1)-1     , n(2)+1:2*n(2), n(3)+1:2*n(3)-1, :) = u_wc(3:Bs(1)+2*g-1:2 , 2:Bs(2)+2*g:2, 3:Bs(3)+2*g-1:2, :)
                u_wc_tmp( n(1)+1:2*n(1)-1, n(2)+1:2*n(2)-1, n(3)+1:2*n(3)-1, :) = u_wc(3:Bs(1)+2*g-1:2 , 3:Bs(2)+2*g-1:2, 3:Bs(3)+2*g-1:2, :)
            endif

            if (allocated(buffer1)) then
                if (size(buffer1, dim=1)/=nx) deallocate(buffer1)
            endif
            if (.not.allocated(buffer1)) allocate(buffer1(1:nx))
            if (allocated(buffer2)) then
                if (size(buffer2, dim=1)/=nx) deallocate(buffer2)
            endif
            if (.not.allocated(buffer2)) allocate(buffer2(1:nx))
            if (allocated(buffer3)) then
                if (size(buffer3, dim=1)/=nx) deallocate(buffer3)
            endif
            if (.not.allocated(buffer3)) allocate(buffer3(1:nx))

            do ic = 1, nc
                do iy = 1, ny ! TODO: may run (g+1),... exclude ghosts
                    do iz = 1, nz
                        ! fill upsampling buffer for low-pass filter: every second point
                        ! apply low-pass filter to upsampled signal
                        buffer3 = 0.0_rk
                        ! odd g, 2nd point is collocation point
                        buffer3(2:nx:2) = u_wc_tmp(1:n(1), iy, iz, ic) ! SC
                        call filter1G(params, buffer3, buffer1, params%HR, lbound(params%HR,dim=1), ubound(params%HR,dim=1))

                        ! fill upsampling buffer for high-pass filter: every second point
                        buffer3 = 0.0_rk
                        buffer3(2:nx:2) = u_wc_tmp(n(1)+1:2*n(1), iy, iz, ic) ! WC
                        ! buffer3(1:nx-1:2) = u_wc_tmp(n(1)+1:2*n(1), iy, iz, ic) ! WC
                        call filter1G(params, buffer3, buffer2, params%GR, lbound(params%GR,dim=1), ubound(params%GR,dim=1))

                        u_wc(:, iy, iz, ic) = buffer2 + buffer1
                    enddo
                enddo
            enddo

            if (allocated(buffer1)) then
                if (size(buffer1, dim=1)/=ny) deallocate(buffer1)
            endif
            if (.not.allocated(buffer1)) allocate(buffer1(1:ny))
            if (allocated(buffer2)) then
                if (size(buffer2, dim=1)/=ny) deallocate(buffer2)
            endif
            if (.not.allocated(buffer2)) allocate(buffer2(1:ny))
            if (allocated(buffer3)) then
                if (size(buffer3, dim=1)/=ny) deallocate(buffer3)
            endif
            if (.not.allocated(buffer3)) allocate(buffer3(1:ny))

            do ic = 1, nc
                do ix = 1, nx
                    do iz = 1, nz
                        ! fill upsampling buffer for low-pass filter: every second point
                        ! apply low-pass filter to upsampled signal
                        buffer3 = 0.0_rk
                        buffer3(2:ny:2) = u_wc(ix, 1:n(2), iz, ic)
                        call filter1G(params, buffer3, buffer1, params%HR, lbound(params%HR,dim=1), ubound(params%HR,dim=1))

                        ! fill upsampling buffer for high-pass filter: every second point
                        buffer3 = 0.0_rk
                        buffer3(2:ny:2) = u_wc(ix, n(2)+1:2*n(2), iz, ic)
                        call filter1G(params, buffer3, buffer2, params%GR, lbound(params%GR,dim=1), ubound(params%GR,dim=1))

                        u_wc(ix, :, iz, ic) = buffer2 + buffer1
                    enddo
                enddo
            enddo

            !!!!!!!!!!!!!!!!!
            if (nz==1) return
            !!!!!!!!!!!!!!!!!

            if (allocated(buffer1)) then
                if (size(buffer1, dim=1)/=nz) deallocate(buffer1)
            endif
            if (.not.allocated(buffer1)) allocate(buffer1(1:nz))
            if (allocated(buffer2)) then
                if (size(buffer2, dim=1)/=nz) deallocate(buffer2)
            endif
            if (.not.allocated(buffer2)) allocate(buffer2(1:nz))
            if (allocated(buffer3)) then
                if (size(buffer3, dim=1)/=nz) deallocate(buffer3)
            endif
            if (.not.allocated(buffer3)) allocate(buffer3(1:nz))

            do ic = 1, nc
                do ix = 1, nx
                    do iy = 1, ny
                        ! fill upsampling buffer for low-pass filter: every second point
                        ! apply low-pass filter to upsampled signal
                        buffer3 = 0.0_rk
                        buffer3(2:ny:2) = u_wc(ix, iy, 1:n(3), ic)
                        call filter1G(params, buffer3, buffer1, params%HR, lbound(params%HR,dim=1), ubound(params%HR,dim=1))

                        ! fill upsampling buffer for high-pass filter: every second point
                        buffer3 = 0.0_rk
                        buffer3(2:ny:2) = u_wc(ix, iy, n(3)+1:2*n(3), ic)
                        call filter1G(params, buffer3, buffer2, params%GR, lbound(params%GR,dim=1), ubound(params%GR,dim=1))

                        u_wc(ix, iy, :, ic) = buffer2 + buffer1
                    enddo
                enddo
            enddo

        endif

    end subroutine






end module
