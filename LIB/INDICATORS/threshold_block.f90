subroutine threshold_block( params, u, thresholding_component, refinement_status, norm, level, detail_precomputed, eps )
    implicit none

    !> user defined parameter structure
    type (type_params), intent(in)      :: params
    !> heavy data - this routine is called on one block only, not on the entire grid. hence th 4D array.
    real(kind=rk), intent(inout)        :: u(:, :, :, :)
    !> it can be useful not to consider all components for thresholding here.
    !! e.g. to work only on the pressure or vorticity.
    logical, intent(in)                 :: thresholding_component(:)
    !> main output of this routine is the new satus
    integer(kind=ik), intent(out)       :: refinement_status
    ! If we use L2 or H1 normalization, the threshold eps is level-dependent, hence
    ! we pass the level to this routine
    integer(kind=ik), intent(in)        :: level
    !
    real(kind=rk), intent(inout)        :: norm( size(u,4) )
    ! if different from the default eps (params%eps), you can pass a different value here. This is optional
    ! and used for example when thresholding the mask function.
    real(kind=rk), intent(in), optional :: eps
    real(kind=rk), intent(inout)        :: detail_precomputed(:)

    integer(kind=ik)                    :: dF, i, j, l, p
    real(kind=rk)                       :: detail( size(u,4) )
    integer(kind=ik)                    :: g, dim, Jmax, nx, ny, nz, nc
    integer(kind=ik), dimension(3)      :: Bs
    real(kind=rk)                       :: t0, eps2
    ! The WC array contains SC (scaling function coeffs) as well as all WC (wavelet coeffs)
    ! Note: the precise naming of SC/WC is not really important. we just apply
    ! the correct decomposition/reconstruction filters - thats it.
    !
    ! INDEX            2D     3D     LABEL (NAME)
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
    real(kind=rk), allocatable, dimension(:,:,:,:,:), save :: wc
    real(kind=rk), allocatable, dimension(:,:,:,:), save :: u_wc

    t0     = MPI_Wtime()
    nx     = size(u, 1)
    ny     = size(u, 2)
    nz     = size(u, 3)
    nc     = size(u, 4)
    Bs     = params%Bs
    g      = params%g
    dim    = params%dim
    Jmax   = params%Jmax
    detail = -1.0_rk

    if (allocated(u_wc)) then
        if (.not. areArraysSameSize(u, u_wc) ) deallocate(u_wc)
    endif
    if (allocated(wc)) then
        if (.not. areArraysSameSize(u, wc(:,:,:,:,1)) ) deallocate(wc)
    endif

    if (.not. allocated(wc)) allocate(wc(1:nx, 1:ny, 1:nz, 1:nc, 1:8) )
    if (.not. allocated(u_wc)) allocate(u_wc(1:nx, 1:ny, 1:nz, 1:nc ) )


#ifdef DEV
    if (.not. allocated(params%GD)) call abort(1213149, "The cat is angry: Wavelet-setup not yet called?")
    if (modulo(Bs(1),2) /= 0) call abort(1213150, "The dog is angry: Block size must be even.")
    if (modulo(Bs(2),2) /= 0) call abort(1213150, "The dog is angry: Block size must be even.")
#endif

    ! no precomputed detail available, compute it here.
    if (detail_precomputed(1) < -0.1_rk) then
        ! write(*,*) "recomputing"
        ! perform the wavlet decomposition of the block
        ! Note we could not reonstruct here, because the neighboring WC/SC are not
        ! synced. However, here, we only check the details on a block, so there is no
        ! need for reconstruction.
        u_wc = u
        call waveletDecomposition_block(params, u_wc) ! data on u (WC/SC) now in Spaghetti order

        ! NOTE: if the coarse reconstruction is performed before this routine is called, then
        ! the WC affected by the coarseExtension are automatically zero. There is no need to reset
        ! them again. -> checked in postprocessing that this is indeed the case.
        call spaghetti2inflatedMallat_block(params, u_wc, wc)

        if (params%dim == 2) then
            do p = 1, nc
                ! if all details are smaller than C_eps, we can coarsen.
                ! check interior WC only
                detail(p) = maxval( abs(wc(g+1:Bs(1)+g, g+1:Bs(2)+g, :, p, 2:4)) )
            enddo
        else
            do p = 1, nc
                ! if all details are smaller than C_eps, we can coarsen.
                ! check interior WC only
                detail(p) = maxval( abs(wc(g+1:Bs(1)+g, g+1:Bs(2)+g, g+1:Bs(3)+g, p, 2:8)) )
            enddo
        endif

    else
        ! detail is precomputed in coarseExtensionUpdate_tree (because we compute
        ! the FWT there anyways)
        detail(1:nc) = detail_precomputed(1:nc)
    endif

    detail(1:nc) = detail(1:nc) / norm(1:nc)

    ! Disable detail checking for qtys we do not want to consider. NOTE FIXME this
    ! is not very efficient, as it would be better to not even compute the wavelet transform
    ! in the first place (but this is more work and selective thresholding is rarely used..)
    do p = 1, nc
        if (.not. thresholding_component(p)) detail(p) = 0.0_rk
    enddo

    ! ich habe die wavelet normalization ausgebruetet und aufgeschrieben.
    ! ich schicke dir die notizen gleich (photos).
    !
    ! also wir brauchen einen scale(level)- dependent threshold, d.h. \epsilon_j
    ! zudem ist dieser abhaengig von der raum dimension d.
    !
    ! Fuer die L^2 normalisierung (mit wavelets welche in der L^\infty norm normalisiert sind) haben wir
    !
    ! \epsilon_j = 2^{-jd/2} \epsilon
    !
    ! d.h. der threshold wird kleiner auf kleinen skalen.
    !
    ! Fuer die vorticity (anstatt der velocity) kommt nochmal ein faktor 2^{-j} dazu, d.h.
    !
    ! \epsilon_j = 2^{-j(d+2)/2} \epsilon
    !
    ! Zum testen waere es gut in 1d oder 2d zu pruefen, ob die L^2 norm von u - u_\epsilon
    ! linear mit epsilon abnimmt, das gleiche koennte man auch fuer H^1 (philipp koennte dies doch mal ausprobieren?).
    !
    ! fuer CVS brauchen wir dann noch \epsilon was von Z (der enstrophy) und der feinsten
    ! aufloesung abhaengt. fuer L^2 normalisierte wavelets ist
    ! der threshold:
    !
    ! \epsilon = \sqrt{2/3 \sigma^2 \ln N}
    !
    ! wobei \sigma^2 die varianz (= 2 Z) der incoh. vorticity ist.
    ! typischerweise erhaelt man diese mit 1-3 iterationen.
    ! als ersten schritt koennen wir einfach Z der totalen stroemung nehmen.
    ! N ist die maximale aufloesung, typicherweise 2^{d J}.
    !

    ! default thresholding level is the one in the parameter struct
    eps2 = params%eps
    ! but if we pass another one, use that.
    if (present(eps)) eps2 = eps


    select case(params%eps_norm)
    case ("Linfty")
        ! do nothing, our wavelets are normalized in L_infty norm by default, hence
        ! a simple threshold controls this norm
        eps2 = eps2

    case ("L2")
        ! If we want to control the L2 norm (with wavelets that are normalized in Linfty norm)
        ! we have to have a level-dependent threshold
        eps2 = eps2 * ( 2.0_rk**(-dble((level-Jmax)*params%dim)/2.0_rk) )

    case ("H1")
        ! H1 norm mimicks filtering of vorticity
        eps2 = eps2 * ( 2**(-level*(params%dim+2.0_rk)*0.5_rk) )

    case default
        call abort(20022811, "ERROR:threshold_block.f90:Unknown wavelet normalization!")

    end select

    ! evaluate criterion: if this blocks detail is smaller than the prescribed precision,
    ! the block is tagged as "wants to coarsen" by setting the tag -1
    ! note gradedness and completeness may prevent it from actually going through with that
    if ( maxval(detail) < eps2) then
        ! coarsen block, -1
        refinement_status = -1
    else
        refinement_status = 0
    end if

    ! timings
    call toc( "threshold_block (w/o ghost synch.)", MPI_Wtime() - t0 )
end subroutine threshold_block
