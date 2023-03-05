! subroutine waveletDecomposition_tree( params, lgt_block, hvy_block, hvy_work, hvy_neighbor, hvy_active, hvy_n )
!     implicit none
!
!     type (type_params), intent(in)      :: params
!     !> light data array
!     integer(kind=ik), intent(in)        :: lgt_block(:, :)
!     !> heavy data array - block data
!     real(kind=rk), intent(inout)        :: hvy_block(:, :, :, :, :)
!     real(kind=rk), intent(inout)        :: hvy_work(:, :, :, :, :)
!     !> heavy data array - neighbor data
!     integer(kind=ik), intent(in)        :: hvy_neighbor(:,:)
!     !> list of active blocks (heavy data)
!     integer(kind=ik), intent(in)        :: hvy_active(:)
!     !> number of active blocks (heavy data)
!     integer(kind=ik), intent(in)        :: hvy_n
!
!     integer(kind=ik) :: N, k, neighborhood, level_diff, hvyID, lgtID, hvyID_neighbor, lgtID_neighbor, level_me, level_neighbor, Nwcl
!     integer(kind=ik) :: nx,ny,nz,nc, g, Bs(1:3), Nwcr, ii, Nscl, Nscr, Nreconl, Nreconr
!     real(kind=rk), allocatable, dimension(:,:,:,:), save :: sc, wcx, wcy, wcxy, tmp_reconst
!
!     nx = size(hvy_block, 1)
!     ny = size(hvy_block, 2)
!     nz = size(hvy_block, 3)
!     nc = size(hvy_block, 4)
!     g  = params%g
!     Bs = params%bs
!
!     if (.not. allocated(sc  )) allocate(  sc(1:nx, 1:ny, 1:nz, 1:nc) )
!     if (.not. allocated(wcx )) allocate( wcx(1:nx, 1:ny, 1:nz, 1:nc) )
!     if (.not. allocated(wcy )) allocate( wcy(1:nx, 1:ny, 1:nz, 1:nc) )
!     if (.not. allocated(wcxy)) allocate(wcxy(1:nx, 1:ny, 1:nz, 1:nc) )
!     if (.not. allocated(tmp_reconst)) allocate(tmp_reconst(1:nx, 1:ny, 1:nz, 1:nc) )
!
!     !~~~~~~~~~~~~~setup~~~~~~~~~~~~~~~~~~
!     select case(params%wavelet)
!     case ("CDF44")
!         ! NOTE: there is a story with even and odd numbers here. Simply, every 2nd
!         ! value of SC/WC is zero anyways (in the reconstruction, see also setRequiredZerosWCSC_block)
!         ! So for example deleting g+5 and g+6 does not make any difference, because the 6th is zero anyways
!         ! scaling function coeffs to be copied:
!         Nscl = g+5 ! dictated by support of h_tilde (HD) filter for SC
!         Nscr = g+5
!         ! wavelet coefficients to be deleted:
!         Nwcl = Nscl+3 ! chosen such that g_tilde (GD) not not see the copied SC
!         Nwcr = Nscr+5
!         ! last reocnstructed point is the support of GR filter not seing any WC set to zero anymore
!         Nreconl = Nwcl+7 ! support of GR -7:5
!         Nreconr = Nwcr+5
!
!     case ("CDF42")
!         Nscl = g+3
!         Nscr = g+3
!         Nwcl = Nscl+3 ! chosen such that g_tilde (GD) not not see the copied SC
!         Nwcr = Nscr+5
!         Nreconl = Nwcl+5 ! support of GR -5:3
!         Nreconr = Nwcr+3
!
!     case ("CDF22")
!         Nscl = g+1
!         Nscr = g+1
!         Nwcl = Nscl + 0 ! chosen such that g_tilde (GD) not not see the copied SC
!         Nwcr = Nscr + 2
!         Nreconl = Nwcl+3 ! support of GR -3:1
!         Nreconr = Nwcr+1
!
!     case default
!         call abort(23030416, "Unknown wavelet. How about a cup of coffee? Go make some.")
!     end select
!     !~~~~~~~~~~~~~setup~~~~~~~~~~~~~~~~~~
!
!     ! maybe this call is redundant - FIXME
!     ! First, we sync the ghost nodes, in order to apply the decomposition filters
!     ! HD and GD to the data. It may be that this is done before calling.
!     call sync_ghosts( params, lgt_block, hvy_block, hvy_neighbor, hvy_active, hvy_n )
!
!
!     ! 2nd. We compute the decomposition by applying the HD GD filters to the data.
!     ! Data are decimated and then stored in the block in Spaghetti order (the counterpart
!     ! to Mallat ordering). Coefficients SC and WC are computed only inside the block
!     ! not in the ghost nodes (that is trivial: we cannot compute the filters in the ghost node
!     ! layer). The first point [(g+1),(g+1)] is a scaling function coefficient, regardless of g
!     ! odd or even. Bs must be even. We also make a copy of the sync'ed data n hvy_work - we use this
!     ! to fix up the SC in the coarse extension case.
!     do k = 1, hvy_n
!         hvyID = hvy_active(k)
!         ! hvy_work now is a copy with sync'ed ghost points.
!         hvy_work(:,:,:,1:nc,hvyID) = hvy_block(:,:,:,1:nc,hvyID)
!
!         ! data WC/SC now in Spaghetti order
!         call waveletDecomposition_block(params, hvy_block(:,:,:,:,hvyID))
!     end do
!
!
!     ! 3rd we sync the decompose coefficients, but only on the same level. This is
!     ! required as several fine blocks hit a coarse one, and this means we have to sync
!     ! those in order to be able to reconstruct with modified WC/SC. Note it does not matter
!     ! if all blocks are sync'ed: we'll not reconstruct on the coarse block anyways, and the
!     ! ghost nodes on the fine bloc (WC/SC) are overwritten in the coarse-extension assumption anyways.
!     call sync_ghosts( params, lgt_block, hvy_block, hvy_neighbor, hvy_active, hvy_n, syncSameLevelOnly1=.true. )
!
!     ! at this point, we would be done on an equidistant grid. however, now, we must
!     ! modify some SC/WC.
!
!     ! routine operates on a single tree (not a forest)
!     ! 4th. Loop over all blocks and check if they have *coarser* neighbors. Neighborhood 1..4 are
!     ! always equidistant.
!     do k = 1, hvy_n
!         hvyID = hvy_active(k)
!         call hvy2lgt( lgtID, hvyID, params%rank, params%number_blocks )
!
!         call spaghetti2mallat_block(params, hvy_block(:,:,:,:,hvyID), sc, wcx, wcy, wcxy)
!
!         ! loop over all relevant neighbors
!         do neighborhood = 5, 16
!             ! neighbor exists ?
!             if ( hvy_neighbor(hvyID, neighborhood) /= -1 ) then
!                 ! neighbor light data id
!                 lgtID_neighbor = hvy_neighbor( hvyID, neighborhood )
!                 level_me       = lgt_block( lgtID, params%Jmax + IDX_MESH_LVL )
!                 level_neighbor = lgt_block( lgtID_neighbor, params%Jmax + IDX_MESH_LVL )
!
!                 ! manipulation of coeffs - my neighbor is coarser
!                 if (level_neighbor < level_me) then
!                     select case(neighborhood)
!                     case (9:10)
!                         ! -x
!                         ! NOTE: even though we set Nwcl=12 points to zero, this does not mean we
!                         ! kill 12 WC. They are on the extended grid, so effectively only 12/2
!                         ! are killed, many of which are in the ghost nodes layer
!                         wcx(1:Nwcl, :, :, 1:nc) = 0.0_rk
!                         wcy(1:Nwcl, :, :, 1:nc) = 0.0_rk
!                         wcxy(1:Nwcl, :, :, 1:nc) = 0.0_rk
!                         sc(1:Nscl, :, :, 1:nc) = hvy_work(1:Nscl,:,:,1:nc,hvyID)
!                     case (15:16)
!                         ! -y
!                         wcx(:, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcy(:, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcxy(:, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         sc(:, 1:Nscl, :, 1:nc) = hvy_work(:, 1:Nscl,:,1:nc,hvyID)
!                     case (11:12)
!                         ! +x
!                         wcx(nx-Nwcr:nx, :, :, 1:nc) = 0.0_rk
!                         wcy(nx-Nwcr:nx, :, :, 1:nc) = 0.0_rk
!                         wcxy(nx-Nwcr:nx, :, :, 1:nc) = 0.0_rk
!                         sc(nx-Nscr:nx, :, :, 1:nc) = hvy_work(nx-Nscr:nx,:,:,1:nc,hvyID)
!                     case (13:14)
!                         ! +y
!                         wcx(:, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcy(:, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcxy(:, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         sc(:, ny-Nscr:ny, :, 1:nc) = hvy_work(:, ny-Nscr:ny,:,1:nc,hvyID)
!                     case(5)
!                         wcx(1:Nwcl, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcy(1:Nwcl, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcxy(1:Nwcl, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         sc(1:Nscl, ny-Nscr:ny, :, 1:nc) = hvy_work(1:Nscl, ny-Nscr:ny,:,1:nc,hvyID)
!                     case(6)
!                         wcx(1:Nwcl, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcy(1:Nwcl, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcxy(1:Nwcl, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         sc(1:Nscl, 1:Nscl, :, 1:nc) = hvy_work(1:Nscl, 1:Nscl,:,1:nc,hvyID)
!                     case(7)
!                         wcx(nx-Nwcr:ny, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcy(nx-Nwcr:ny, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcxy(nx-Nwcr:ny, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         sc(nx-Nscr:ny, ny-Nscr:ny, :, 1:nc) = hvy_work(nx-Nscr:ny, ny-Nscr:ny,:,1:nc,hvyID)
!                     case(8)
!                         wcx(nx-Nwcr:ny, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcy(nx-Nwcr:ny, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcxy(nx-Nwcr:ny, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         sc(nx-Nscr:ny, 1:Nscl, :, 1:nc) = hvy_work(nx-Nscr:ny, 1:Nscl,:,1:nc,hvyID)
!                     end select
!                 endif
!
!                 ! manipulation of coeffs - my neighbor is finer
!                 ! this simply means removing the WC in the ghost node layer
!                 if (level_neighbor > level_me) then
!                     select case(neighborhood)
!                     case (9:10)
!                         ! -x
!                         ! NOTE: even though we set Nwcl=12 points to zero, this does not mean we
!                         ! kill 12 WC. They are on the extended grid, so effectively only 12/2
!                         ! are killed, many of which are in the ghost nodes layer
!                         wcx(1:Nwcl, :, :, 1:nc) = 0.0_rk
!                         wcy(1:Nwcl, :, :, 1:nc) = 0.0_rk
!                         wcxy(1:Nwcl, :, :, 1:nc) = 0.0_rk
!                         sc(1:Nscl, :, :, 1:nc) = hvy_work(1:Nscl,:,:,1:nc,hvyID)
!                     case (15:16)
!                         ! -y
!                         wcx(:, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcy(:, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcxy(:, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         sc(:, 1:Nscl, :, 1:nc) = hvy_work(:, 1:Nscl,:,1:nc,hvyID)
!                     case (11:12)
!                         ! +x
!                         wcx(nx-Nwcr:nx, :, :, 1:nc) = 0.0_rk
!                         wcy(nx-Nwcr:nx, :, :, 1:nc) = 0.0_rk
!                         wcxy(nx-Nwcr:nx, :, :, 1:nc) = 0.0_rk
!                         sc(nx-Nscr:nx, :, :, 1:nc) = hvy_work(nx-Nscr:nx,:,:,1:nc,hvyID)
!                     case (13:14)
!                         ! +y
!                         wcx(:, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcy(:, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcxy(:, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         sc(:, ny-Nscr:ny, :, 1:nc) = hvy_work(:, ny-Nscr:ny,:,1:nc,hvyID)
!                     case(5)
!                         wcx(1:Nwcl, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcy(1:Nwcl, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcxy(1:Nwcl, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         sc(1:Nscl, ny-Nscr:ny, :, 1:nc) = hvy_work(1:Nscl, ny-Nscr:ny,:,1:nc,hvyID)
!                     case(6)
!                         wcx(1:Nwcl, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcy(1:Nwcl, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcxy(1:Nwcl, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         sc(1:Nscl, 1:Nscl, :, 1:nc) = hvy_work(1:Nscl, 1:Nscl,:,1:nc,hvyID)
!                     case(7)
!                         wcx(nx-Nwcr:ny, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcy(nx-Nwcr:ny, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcxy(nx-Nwcr:ny, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         sc(nx-Nscr:ny, ny-Nscr:ny, :, 1:nc) = hvy_work(nx-Nscr:ny, ny-Nscr:ny,:,1:nc,hvyID)
!                     case(8)
!                         wcx(nx-Nwcr:ny, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcy(nx-Nwcr:ny, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcxy(nx-Nwcr:ny, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         sc(nx-Nscr:ny, 1:Nscl, :, 1:nc) = hvy_work(nx-Nscr:ny, 1:Nscl,:,1:nc,hvyID)
!                     end select
!                 endif
!             endif
!         enddo
!
!         ! copy back original data, then fix the coarse extension parts by
!         ! copying tmp_reconst (the inverse of the manipulated SC/WC) into the patches
!         ! relevant for coarse extension
!         hvy_block(:,:,:,1:nc,hvyID) = hvy_work(:,:,:,1:nc,hvyID)
!
!         if (manipulated) then
!             ! ensures that 3/4 of the numbers are zero - required for reconstruction
!             ! note when copying Spaghetti to Mallat, this is automatically done, but
!             ! when manipulating coefficients, it may happen that we set nonzero values
!             ! where a zero should be. Here: only SC (WC are set to zero anyways)
!             call setRequiredZerosWCSC_block(params, sc)
!             ! wavelet reconstruction - we do not call the routine in module_interplation
!             ! because this requires us to copy data back to Spaghetti-ordering (which is
!             ! unnecessary here, even though it would not hurt)
!             call blockFilterCustom_vct( params, sc  , sc  , "HR", "HR", "--" )
!             call blockFilterCustom_vct( params, wcx , wcx , "HR", "GR", "--" )
!             call blockFilterCustom_vct( params, wcy , wcy , "GR", "HR", "--" )
!             call blockFilterCustom_vct( params, wcxy, wcxy, "GR", "GR", "--" )
!             tmp_reconst = sc + wcx + wcy + wcxy
!
!             ! reconstruction part. We manipulated the data and reconstructed it in some regions.
!             ! Now, we copy those reconstructed data back to the original block - this is
!             ! the actual coarseExtension.
!             do neighborhood = 5, 16
!                 if ( hvy_neighbor(hvyID, neighborhood) /= -1 ) then
!                     ! neighbor light data id
!                     lgtID_neighbor = hvy_neighbor( hvyID, neighborhood )
!                     level_me       = lgt_block( lgtID, params%Jmax + IDX_MESH_LVL )
!                     level_neighbor = lgt_block( lgtID_neighbor, params%Jmax + IDX_MESH_LVL )
!
!                     if (level_neighbor < level_me) then
!                         ! coarse extension case (neighbor is coarser)
!                         select case (neighborhood)
!                         case (9:10)
!                             ! -x
!                             hvy_block(1:Nreconl, :, :, 1:nc, hvyID) = tmp_reconst(1:Nreconl,:,:,1:nc)
!                         case (11:12)
!                             ! +x
!                             hvy_block(nx-Nreconr:nx, :, :, 1:nc, hvyID) = tmp_reconst(nx-Nreconr:nx,:,:,1:nc)
!                         case (13:14)
!                             ! +y
!                             hvy_block(:, ny-Nreconr:ny, :, 1:nc, hvyID) = tmp_reconst(:, ny-Nreconr:ny,:,1:nc)
!                         case (15:16)
!                             ! -y
!                             hvy_block(:, 1:Nreconl, :, 1:nc, hvyID) = tmp_reconst(:, 1:Nreconl,:,1:nc)
!                         case (5)
!                             hvy_block(1:Nreconl, ny-Nreconr:ny, :, 1:nc, hvyID) = tmp_reconst(1:Nreconl, ny-Nreconr:ny,:,1:nc)
!                         case (6)
!                             hvy_block(1:Nreconl, 1:Nreconl, :, 1:nc, hvyID) = tmp_reconst(1:Nreconl, 1:Nreconl,:,1:nc)
!                         case (7)
!                             ! top right corner
!                             hvy_block(nx-Nreconr:nx, ny-Nreconr:ny, :, 1:nc, hvyID) = tmp_reconst(nx-Nreconr:nx, ny-Nreconr:ny,:,1:nc)
!                         case (8)
!                             hvy_block(nx-Nreconr:nx, 1:Nreconl, :, 1:nc, hvyID) = tmp_reconst(nx-Nreconr:nx, 1:Nreconl,:,1:nc)
!                         end select
!                     endif
!                 endif
!             enddo
!         end if
!     end do
!
!     ! this is probably an optional sync step
!     call sync_ghosts( params, lgt_block, hvy_block, hvy_neighbor, hvy_active, hvy_n )
!
! end subroutine
!
!
!
! subroutine waveletReconstruction_tree( params, lgt_block, hvy_block, hvy_work, hvy_neighbor, hvy_active, hvy_n )
!     implicit none
!
!     type (type_params), intent(in)      :: params
!     !> light data array
!     integer(kind=ik), intent(in)        :: lgt_block(:, :)
!     !> heavy data array - block data
!     real(kind=rk), intent(inout)        :: hvy_block(:, :, :, :, :)
!     real(kind=rk), intent(inout)        :: hvy_work(:, :, :, :, :)
!     !> heavy data array - neighbor data
!     integer(kind=ik), intent(in)        :: hvy_neighbor(:,:)
!     !> list of active blocks (heavy data)
!     integer(kind=ik), intent(in)        :: hvy_active(:)
!     !> number of active blocks (heavy data)
!     integer(kind=ik), intent(in)        :: hvy_n
!
!     integer(kind=ik) :: N, k, neighborhood, level_diff, hvyID, lgtID, hvyID_neighbor, lgtID_neighbor, level_me, level_neighbor, Nwcl
!     integer(kind=ik) :: nx,ny,nz,nc, g, Bs(1:3), Nwcr, ii, Nscl, Nscr, Nreconl, Nreconr
!     real(kind=rk), allocatable, dimension(:,:,:,:), save :: sc, wcx, wcy, wcxy, tmp_reconst
!     logical :: manipulated
!
!     if ((params%wavelet=="CDF40").or.(params%wavelet=="CDF20")) return
!
!     nx = size(hvy_block, 1)
!     ny = size(hvy_block, 2)
!     nz = size(hvy_block, 3)
!     nc = size(hvy_block, 4)
!     g = params%g
!     Bs = params%bs
!
!     if (.not. allocated(sc  )) allocate(  sc(1:nx, 1:ny, 1:nz, 1:nc) )
!     if (.not. allocated(wcx )) allocate( wcx(1:nx, 1:ny, 1:nz, 1:nc) )
!     if (.not. allocated(wcy )) allocate( wcy(1:nx, 1:ny, 1:nz, 1:nc) )
!     if (.not. allocated(wcxy)) allocate(wcxy(1:nx, 1:ny, 1:nz, 1:nc) )
!     if (.not. allocated(tmp_reconst)) allocate(tmp_reconst(1:nx, 1:ny, 1:nz, 1:nc) )
!
!     !~~~~~~~~~~~~~setup~~~~~~~~~~~~~~~~~~
!     select case(params%wavelet)
!     case ("CDF44")
!         ! NOTE: there is a story with even and odd numbers here. Simply, every 2nd
!         ! value of SC/WC is zero anyways (in the reconstruction, see also setRequiredZerosWCSC_block)
!         ! So for example deleting g+5 and g+6 does not make any difference, because the 6th is zero anyways
!         ! scaling function coeffs to be copied:
!         Nscl = g+5 ! dictated by support of h_tilde (HD) filter for SC
!         Nscr = g+5
!         ! wavelet coefficients to be deleted:
!         Nwcl = Nscl+3 ! chosen such that g_tilde (GD) not not see the copied SC
!         Nwcr = Nscr+5
!         ! last reocnstructed point is the support of GR filter not seing any WC set to zero anymore
!         Nreconl = Nwcl+7 ! support of GR -7:5
!         Nreconr = Nwcr+5
!
!     case ("CDF42")
!         Nscl = g+3
!         Nscr = g+3
!         Nwcl = Nscl+3 ! chosen such that g_tilde (GD) not not see the copied SC
!         Nwcr = Nscr+5
!         Nreconl = Nwcl+5 ! support of GR -5:3
!         Nreconr = Nwcr+3
!
!     case ("CDF22")
!         Nscl = g+1
!         Nscr = g+1
!         Nwcl = Nscl + 0 ! chosen such that g_tilde (GD) not not see the copied SC
!         Nwcr = Nscr + 2
!         Nreconl = Nwcl+3 ! support of GR -3:1
!         Nreconr = Nwcr+1
!
!     case default
!         call abort(23030416, "Unknown wavelet. How about a cup of coffee? Go make some.")
!     end select
!     !~~~~~~~~~~~~~setup~~~~~~~~~~~~~~~~~~
!
!     ! maybe this call is redundant - FIXME
!     ! First, we sync the ghost nodes, in order to apply the decomposition filters
!     ! HD and GD to the data. It may be that this is done before calling.
!     call sync_ghosts( params, lgt_block, hvy_block, hvy_neighbor, hvy_active, hvy_n )
!
!
!     ! 2nd. We compute the decomposition by applying the HD GD filters to the data.
!     ! Data are decimated and then stored in the block in Spaghetti order (the counterpart
!     ! to Mallat ordering). Coefficients SC and WC are computed only inside the block
!     ! not in the ghost nodes (that is trivial: we cannot compute the filters in the ghost node
!     ! layer). The first point [(g+1),(g+1)] is a scaling function coefficient, regardless of g
!     ! odd or even. Bs must be even. We also make a copy of the sync'ed data n hvy_work - we use this
!     ! to fix up the SC in the coarse extension case.
!     do k = 1, hvy_n
!         hvyID = hvy_active(k)
!         ! hvy_work now is a copy with sync'ed ghost points.
!         hvy_work(:,:,:,1:nc,hvyID) = hvy_block(:,:,:,1:nc,hvyID)
!
!         ! data WC/SC now in Spaghetti order
!         call waveletDecomposition_block(params, hvy_block(:,:,:,:,hvyID))
!     end do
!
!
!     ! 3rd we sync the decompose coefficients, but only on the same level. This is
!     ! required as several fine blocks hit a coarse one, and this means we have to sync
!     ! those in order to be able to reconstruct with modified WC/SC. Note it does not matter
!     ! if all blocks are sync'ed: we'll not reconstruct on the coarse block anyways, and the
!     ! ghost nodes on the fine bloc (WC/SC) are overwritten in the coarse-extension assumption anyways.
!     call sync_ghosts( params, lgt_block, hvy_block, hvy_neighbor, &
!     hvy_active, hvy_n, syncSameLevelOnly1=.true. )
!
!     ! routine operates on a single tree (not a forest)
!     ! 4th. Loop over all blocks and check if they have *coarser* neighbors. Neighborhood 1..4 are
!     ! always equidistant.
!     do k = 1, hvy_n
!         hvyID = hvy_active(k)
!         call hvy2lgt( lgtID, hvyID, params%rank, params%number_blocks )
!
!
!
!         manipulated = .false.
!         ! loop over all relevant neighbors
!         do neighborhood = 5, 16
!             ! neighbor exists ?
!             if ( hvy_neighbor(hvyID, neighborhood) /= -1 ) then
!                 ! neighbor light data id
!                 lgtID_neighbor = hvy_neighbor( hvyID, neighborhood )
!                 level_me       = lgt_block( lgtID, params%Jmax + IDX_MESH_LVL )
!                 level_neighbor = lgt_block( lgtID_neighbor, params%Jmax + IDX_MESH_LVL )
!
!                 if (level_neighbor < level_me) then
!                     if (.not. manipulated) then ! only on first encounter
!                         sc   = 0.0_rk
!                         wcx  = 0.0_rk
!                         wcy  = 0.0_rk
!                         wcxy = 0.0_rk
!
!                         ! copy from Spaghetti to Mallat ordering
!                         if (modulo(g, 2) == 0) then
!                             ! even g
!                             sc(   1:nx:2, 1:ny:2, :, :) = hvy_block(1:nx:2, 1:ny:2, :, 1:nc, hvyID)
!                             wcx(  1:nx:2, 1:ny:2, :, :) = hvy_block(2:nx:2, 1:ny:2, :, 1:nc, hvyID)
!                             wcy(  1:nx:2, 1:ny:2, :, :) = hvy_block(1:nx:2, 2:ny:2, :, 1:nc, hvyID)
!                             wcxy( 1:nx:2, 1:ny:2, :, :) = hvy_block(2:nx:2, 2:ny:2, :, 1:nc, hvyID)
!                         else
!                             ! odd g
!                             sc(   2:nx-1:2, 2:ny-1:2, :, :) = hvy_block(2:nx-1:2, 2:ny-1:2, :, 1:nc, hvyID)
!                             wcx(  2:nx-1:2, 2:ny-1:2, :, :) = hvy_block(3:nx:2, 2:ny-1:2  , :, 1:nc, hvyID)
!                             wcy(  2:nx-1:2, 2:ny-1:2, :, :) = hvy_block(2:nx-1:2, 3:ny:2  , :, 1:nc, hvyID)
!                             wcxy( 2:nx-1:2, 2:ny-1:2, :, :) = hvy_block(3:nx:2, 3:ny:2    , :, 1:nc, hvyID)
!                         endif
!                     endif
!                     manipulated = .true.
!
!                     ! write(*,*) trim(adjustl(params%wavelet)), Nscl, Nscr, Nwcl, Nwcr
!
!                     ! manipulation of coeffs
!                     select case(neighborhood)
!                     case (9:10)
!                         ! -x
!                         ! FIXME to be modified for any other than CDF44
!                         ! NOTE: even though we set Nwcl=12 points to zero, this does not mean we
!                         ! kill 12 WC. They are on the extended grid, so effectively only 12/2
!                         ! are killed, many of which are in the ghost nodes layer
!                         wcx(1:Nwcl, :, :, 1:nc) = 0.0_rk
!                         wcy(1:Nwcl, :, :, 1:nc) = 0.0_rk
!                         wcxy(1:Nwcl, :, :, 1:nc) = 0.0_rk
!                         sc(1:Nscl, :, :, 1:nc) = hvy_work(1:Nscl,:,:,1:nc,hvyID)
!                     case (15:16)
!                         ! -y
!                         wcx(:, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcy(:, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcxy(:, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         sc(:, 1:Nscl, :, 1:nc) = hvy_work(:, 1:Nscl,:,1:nc,hvyID)
!                     case (11:12)
!                         ! +x
!                         wcx(nx-Nwcr:nx, :, :, 1:nc) = 0.0_rk
!                         wcy(nx-Nwcr:nx, :, :, 1:nc) = 0.0_rk
!                         wcxy(nx-Nwcr:nx, :, :, 1:nc) = 0.0_rk
!                         sc(nx-Nscr:nx, :, :, 1:nc) = hvy_work(nx-Nscr:nx,:,:,1:nc,hvyID)
!                     case (13:14)
!                         ! +y
!                         wcx(:, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcy(:, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcxy(:, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         sc(:, ny-Nscr:ny, :, 1:nc) = hvy_work(:, ny-Nscr:ny,:,1:nc,hvyID)
!                     case(5)
!                         wcx(1:Nwcl, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcy(1:Nwcl, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcxy(1:Nwcl, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         sc(1:Nscl, ny-Nscr:ny, :, 1:nc) = hvy_work(1:Nscl, ny-Nscr:ny,:,1:nc,hvyID)
!                     case(6)
!                         wcx(1:Nwcl, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcy(1:Nwcl, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcxy(1:Nwcl, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         sc(1:Nscl, 1:Nscl, :, 1:nc) = hvy_work(1:Nscl, 1:Nscl,:,1:nc,hvyID)
!                     case(7)
!                         wcx(nx-Nwcr:ny, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcy(nx-Nwcr:ny, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         wcxy(nx-Nwcr:ny, ny-Nwcr:ny, :, 1:nc) = 0.0_rk
!                         sc(nx-Nscr:ny, ny-Nscr:ny, :, 1:nc) = hvy_work(nx-Nscr:ny, ny-Nscr:ny,:,1:nc,hvyID)
!                     case(8)
!                         wcx(nx-Nwcr:ny, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcy(nx-Nwcr:ny, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         wcxy(nx-Nwcr:ny, 1:Nwcl, :, 1:nc) = 0.0_rk
!                         sc(nx-Nscr:ny, 1:Nscl, :, 1:nc) = hvy_work(nx-Nscr:ny, 1:Nscl,:,1:nc,hvyID)
!                     end select
!                 endif
!             endif
!         enddo
!
!         ! copy back original data, then fix the coarse extension parts by
!         ! copying tmp_reconst (the inverse of the manipulated SC/WC) into the patches
!         ! relevant for coarse extension
!         hvy_block(:,:,:,1:nc,hvyID) = hvy_work(:,:,:,1:nc,hvyID)
!
!         if (manipulated) then
!             ! ensures that 3/4 of the numbers are zero - required for reconstruction
!             ! note when copying Spaghetti to Mallat, this is automatically done, but
!             ! when manipulating coefficients, it may happen that we set nonzero values
!             ! where a zero should be. Here: only SC (WC are set to zero anyways)
!             call setRequiredZerosWCSC_block(params, sc)
!             ! wavelet reconstruction - we do not call the routine in module_interplation
!             ! because this requires us to copy data back to Spaghetti-ordering (which is
!             ! unnecessary here, even though it would not hurt)
!             call blockFilterCustom_vct( params, sc  , sc  , "HR", "HR", "--" )
!             call blockFilterCustom_vct( params, wcx , wcx , "HR", "GR", "--" )
!             call blockFilterCustom_vct( params, wcy , wcy , "GR", "HR", "--" )
!             call blockFilterCustom_vct( params, wcxy, wcxy, "GR", "GR", "--" )
!             tmp_reconst = sc + wcx + wcy + wcxy
!
!             ! reconstruction part. We manipulated the data and reconstructed it in some regions.
!             ! Now, we copy those reconstructed data back to the original block - this is
!             ! the actual coarseExtension.
!             do neighborhood = 5, 16
!                 if ( hvy_neighbor(hvyID, neighborhood) /= -1 ) then
!                     ! neighbor light data id
!                     lgtID_neighbor = hvy_neighbor( hvyID, neighborhood )
!                     level_me       = lgt_block( lgtID, params%Jmax + IDX_MESH_LVL )
!                     level_neighbor = lgt_block( lgtID_neighbor, params%Jmax + IDX_MESH_LVL )
!
!                     if (level_neighbor < level_me) then
!                         ! coarse extension case (neighbor is coarser)
!                         select case (neighborhood)
!                         case (9:10)
!                             ! -x
!                             hvy_block(1:Nreconl, :, :, 1:nc, hvyID) = tmp_reconst(1:Nreconl,:,:,1:nc)
!                         case (11:12)
!                             ! +x
!                             hvy_block(nx-Nreconr:nx, :, :, 1:nc, hvyID) = tmp_reconst(nx-Nreconr:nx,:,:,1:nc)
!                         case (13:14)
!                             ! +y
!                             hvy_block(:, ny-Nreconr:ny, :, 1:nc, hvyID) = tmp_reconst(:, ny-Nreconr:ny,:,1:nc)
!                         case (15:16)
!                             ! -y
!                             hvy_block(:, 1:Nreconl, :, 1:nc, hvyID) = tmp_reconst(:, 1:Nreconl,:,1:nc)
!                         case (5)
!                             hvy_block(1:Nreconl, ny-Nreconr:ny, :, 1:nc, hvyID) = tmp_reconst(1:Nreconl, ny-Nreconr:ny,:,1:nc)
!                         case (6)
!                             hvy_block(1:Nreconl, 1:Nreconl, :, 1:nc, hvyID) = tmp_reconst(1:Nreconl, 1:Nreconl,:,1:nc)
!                         case (7)
!                             ! top right corner
!                             hvy_block(nx-Nreconr:nx, ny-Nreconr:ny, :, 1:nc, hvyID) = tmp_reconst(nx-Nreconr:nx, ny-Nreconr:ny,:,1:nc)
!                         case (8)
!                             hvy_block(nx-Nreconr:nx, 1:Nreconl, :, 1:nc, hvyID) = tmp_reconst(nx-Nreconr:nx, 1:Nreconl,:,1:nc)
!                         end select
!                     endif
!                 endif
!             enddo
!         end if
!     end do
!
!     ! this is probably an optional sync step
!     call sync_ghosts( params, lgt_block, hvy_block, hvy_neighbor, hvy_active, hvy_n )
!
! end subroutine
