
!--------------------------------------------------------------------------------------------------------------------------------------------------------
!> \file
!> \brief Right hand side for 2D navier stokes equation
!>        ---------------------------------------------
!> The right hand side of navier stokes in the skew symmetric form is implemented as follows:
!>\f{eqnarray*}{
!!     \partial_t \sqrt{\rho} &=& -\frac{1}{2J\sqrt{\rho}} \nabla \cdot (\rho \vec{u})-\frac{1}{\sqrt{\rho}}\frac{1}{C_{\rm SP} } (\rho-\rho^{\rm SP}) \\
!!    \partial_t (\sqrt{\rho} u_\alpha) &=& -\frac{1}{2J \sqrt{\rho}}
!!                                          \left[
!!                                                       (u_\alpha \partial_\beta (\rho u_\beta)+
!!                                                        u_\beta \rho \partial_\beta u_\alpha)
!!                                            \right]
!!                                           -\frac{1}{J \sqrt{\rho}} \partial_\beta \tau_{\alpha\beta}
!!                                           -\frac{1}{\sqrt{\rho}} \partial_\alpha p
!!                                            -\frac{1}{\sqrt{\rho}} \frac{1}{C_{\rm SP} }(\rho u_\alpha-\rho^{\rm SP} u_\alpha^{\rm SP})
!!                                           -\frac{\chi}{2\sqrt{\rho}C_\eta} (\rho u_\alpha)\\
!!    \partial_t p &=& -\frac{\gamma}{J} \partial_\beta( u_\beta p) + (\gamma-1)(u_\alpha \partial_\alpha p)
!!                                      +\frac{\gamma -1}{J}
!!                                           \left[
!!                                                       \partial_\alpha(u_\beta \tau_{\alpha\beta}+\phi_\alpha)
!!                                                       - u_\alpha\partial_\beta \tau_{\alpha\beta}
!!                                            \right]   -\frac{\gamma-1}{C_{\rm SP} } (p-p^{\rm SP})
!!                                             -\frac{\chi}{C_\eta} (p -\rho R_s T)
!!\f}
!> \version 0.5
!! \date 08/12/16 - create \n
!!  \date 13/2/18 - include mask and sponge terms (commit 1cf9d2d53ea76e3fa52f887d593fad5826afec88)
!> \author msr
!--------------------------------------------------------------------------------------------------------------------------------------------------------

!>\brief main function of RHS_2D_navier_stokes
subroutine RHS_2D_navier_stokes( g, Bs, x0, delta_x, phi, rhs, boundary_flag)
!---------------------------------------------------------------------------------------------
!
    implicit none

    !> grid parameter
    integer(kind=ik), intent(in)                            :: g, Bs
    !> origin and spacing of the block
    real(kind=rk), dimension(2), intent(in)                 :: x0, delta_x
    !> datafields
    real(kind=rk), intent(in)                               :: phi(:, :, :)
    !> rhs array
    real(kind=rk), intent(inout)                            :: rhs(:, :, :)
    ! when implementing boundary conditions, it is necessary to now if the local field (block)
    ! is adjacent to a boundary, because the stencil has to be modified on the domain boundary.
    ! The boundary_flag tells you if the local field is adjacent to a domain boundary:
    ! boundary_flag(i) can be either 0, 1, -1,
    !  0: no boundary in the direction +/-e_i
    !  1: boundary in the direction +e_i
    ! -1: boundary in the direction - e_i
    ! currently only acessible in the local stage
    integer(kind=2), intent(in)                             :: boundary_flag(3)

    ! adiabatic coefficient
    real(kind=rk)                                           :: gamma_
    ! specific gas constant
    real(kind=rk)                                           :: Rs
    ! isochoric heat capacity
    real(kind=rk)                                           :: Cv
    ! isobaric heat capacity
    real(kind=rk)                                           :: Cp
    ! prandtl number
    real(kind=rk)                                           :: Pr
    ! dynamic viscosity
    real(kind=rk)                                           :: mu0, mu_d, mu, lambda
    ! dissipation switch
    logical                                                 :: dissipation
    ! spacing
    real(kind=rk)                                           :: dx, dy

    ! variables
    real(kind=rk)                                           :: rho(Bs+2*g, Bs+2*g), u(Bs+2*g, Bs+2*g), v(Bs+2*g, Bs+2*g), p(Bs+2*g, Bs+2*g), T(Bs+2*g, Bs+2*g), &
                                                               tau11(Bs+2*g, Bs+2*g), tau22(Bs+2*g, Bs+2*g), tau33(Bs+2*g, Bs+2*g), tau12(Bs+2*g, Bs+2*g)
    ! dummy field
    real(kind=rk)                                           :: dummy(Bs+2*g, Bs+2*g), dummy2(Bs+2*g, Bs+2*g), dummy3(Bs+2*g, Bs+2*g), dummy4(Bs+2*g, Bs+2*g)

    
    ! inverse sqrt(rho) field 
    real(kind=rk)                                           :: phi1_inv(Bs+2*g, Bs+2*g)

    ! loop variables
    integer(kind=ik)                                        :: i, j

    ! optimization
    ! - do not use all ghost nodes (note: use only two ghost nodes to get correct second derivatives)
    ! - write loops explicitly, 
    ! - use multiplication instead of division
    ! - access array in column-major order
    ! - reduce number of additionaly variables -> lead to direct calculation of rhs terms after derivation

!---------------------------------------------------------------------------------------------
! variables initialization

    ! set physics parameters for readability
    gamma_      = params_ns%gamma_
    Rs          = 1.0_rk/params_ns%Rs
    Cv          = params_ns%Cv
    Cp          = params_ns%Cp
    Pr          = params_ns%Pr
    mu0         = params_ns%mu0
    dissipation = params_ns%dissipation

    ! primitive variables
    do j = 1, Bs+2*g
        do i = 1, Bs+2*g
            rho(i,j)       = phi(i,j,1) * phi(i,j,1)
            phi1_inv(i,j)  = 1.0_rk / phi(i,j,1)
            u(i,j)         = phi(i,j,2) * phi1_inv(i,j)
            v(i,j)         = phi(i,j,3) * phi1_inv(i,j)
            p(i,j)         = phi(i,j,4)
        end do
    end do

    ! Compute mu and T
    if (dissipation) then
        do j = 1, Bs+2*g
            do i = 1, Bs+2*g
                T(i,j) = p(i,j) * phi1_inv(i,j) * phi1_inv(i,j) * Rs
            end do
        end do
        mu   = mu0
        mu_d = 0.0_rk
        ! thermal conductivity
        lambda= Cp * mu/Pr
    end if

    ! discretization constant
    dx = delta_x(1)
    dy = delta_x(2)

!---------------------------------------------------------------------------------------------
! main body

    ! derivatives
    ! u_x, u_y
    !---------------------------------------------------------------------------------------------
    call diffxy_c_opt( Bs, g, dx, dy, u, dummy, dummy2)

    do j = g+1, Bs+g
        do i = g+1, Bs+g
            rhs(i,j,2) = - 0.5_rk * rho(i,j) * ( u(i,j) * dummy(i,j) + v(i,j) * dummy2(i,j))
        end do
    end do

    if (dissipation) then
        ! u_x
        tau11 = ( mu * 2.0_rk +  mu_d - 2.0_rk/3.0_rk * mu ) * dummy
        tau22 = ( mu_d - 2.0_rk/3.0_rk * mu ) * dummy
        tau33 = ( mu_d - 2.0_rk/3.0_rk * mu ) * dummy      
        ! u_y
        tau12 = mu * dummy2         
    end if

    ! v_x, v_y
    !---------------------------------------------------------------------------------------------
    call diffxy_c_opt( Bs, g, dx, dy, v, dummy, dummy2)

    do j = g+1, Bs+g
        do i = g+1, Bs+g
            rhs(i,j,3) = - 0.5_rk * rho(i,j) * ( u(i,j) * dummy(i,j) + v(i,j) * dummy2(i,j))
        end do
    end do

    if (dissipation) then
        ! v_x
        tau12 = tau12 + mu * dummy        
        ! v_y
        tau11 = tau11 + ( mu_d - 2.0_rk/3.0_rk * mu ) * dummy2
        tau22 = tau22 + ( mu * 2.0_rk + mu_d - 2.0_rk/3.0_rk * mu ) * dummy2
        tau33 = tau33 + ( mu_d - 2.0_rk/3.0_rk * mu ) * dummy2        
    end if

    ! p_x, p_y
    !---------------------------------------------------------------------------------------------
    call diffxy_c_opt( Bs, g, dx, dy, p, dummy, dummy2)

    do j = g+1, Bs+g
        do i = g+1, Bs+g
            rhs(i,j,2) = rhs(i,j,2) - dummy(i,j)
            rhs(i,j,3) = rhs(i,j,3) - dummy2(i,j)
            rhs(i,j,4) = (gamma_ - 1.0_rk) * ( u(i,j) * dummy(i,j) + v(i,j) * dummy2(i,j) )
        end do
    end do

    ! friction
    if (dissipation) then

        ! Friction terms for Momentum equation = div(tau_i*)/(J*srho)
        ! tau11_x
        !---------------------------------------------------------------------------------------------
        call diffx_c_opt( Bs, g, dx, tau11, dummy)
        
        do j = g+1, Bs+g
            do i = g+1, Bs+g
                rhs(i,j,2) = rhs(i,j,2) + dummy(i,j)
                rhs(i,j,4) = rhs(i,j,4) - ( gamma_ - 1.0_rk ) * u(i,j) * dummy(i,j) 
            end do
        end do

        ! tau12_y
        !---------------------------------------------------------------------------------------------
        call diffy_c_opt( Bs, g, dy, tau12, dummy)

        do j = g+1, Bs+g
            do i = g+1, Bs+g
                rhs(i,j,2) = rhs(i,j,2) + dummy(i,j)
                rhs(i,j,4) = rhs(i,j,4) - ( gamma_ - 1.0_rk ) * u(i,j) * dummy(i,j) 
            end do
        end do

        ! tau12_x
        !---------------------------------------------------------------------------------------------
        call diffx_c_opt( Bs, g, dx, tau12, dummy)

        do j = g+1, Bs+g
            do i = g+1, Bs+g
                rhs(i,j,3) = rhs(i,j,3) + dummy(i,j)
                rhs(i,j,4) = rhs(i,j,4) - ( gamma_ - 1.0_rk ) * v(i,j) * dummy(i,j)
            end do
        end do

        ! tau22_y
        !---------------------------------------------------------------------------------------------
        call diffy_c_opt( Bs, g, dy, tau22, dummy)

        do j = g+1, Bs+g
            do i = g+1, Bs+g
                rhs(i,j,3) = rhs(i,j,3) + dummy(i,j)
                rhs(i,j,4) = rhs(i,j,4) - ( gamma_ - 1.0_rk ) * v(i,j) * dummy(i,j)
            end do
        end do

        ! Friction terms for the energy equation
        ! Heat Flux
        call diffxy_c_opt( Bs, g, dx, dy, T, dummy, dummy2)

        do j = g-1, Bs+g+2
            do i = g-1, Bs+g+2
                dummy3(i,j)  = u(i,j)*tau11(i,j) + v(i,j)*tau12(i,j) + lambda * dummy(i,j)
                dummy4(i,j) = u(i,j)*tau12(i,j) + v(i,j)*tau22(i,j) + lambda * dummy2(i,j)
            end do
        end do
        call diffx_c_opt( Bs, g, dx, dummy3, dummy)
        call diffy_c_opt( Bs, g, dy, dummy4, dummy2)

        do j = g+1, Bs+g
            do i = g+1, Bs+g
                rhs(i,j,4) = rhs(i,j,4) + ( gamma_ - 1.0_rk ) * ( dummy(i,j) + dummy2(i,j) )
            end do
        end do

    end if

    ! EQUATIONS
    ! --------------------------------------------------------------------------------------------------------------
    ! RHS of equation of mass: J*srho*2 * srho_t = -div(rho*U_tilde)
    do j = g-1, Bs+g+2
        do i = g-1, Bs+g+2
            dummy(i,j)  = rho(i,j)*u(i,j)
            dummy2(i,j) = rho(i,j)*v(i,j)
        end do
    end do
    call diffx_c_opt( Bs, g, dx, dummy,  dummy3)
    call diffy_c_opt( Bs, g, dy, dummy2, dummy4)

    do j = g+1, Bs+g
        do i = g+1, Bs+g
            rhs(i,j,1) = (-dummy3(i,j) - dummy4(i,j)) * 0.5_rk * phi1_inv(i,j)
        end do
    end do

    ! RHS of  momentum equation for u: sru_t = -1/2 * div(rho U_tilde u ) - 1/2 * (rho*U_tilde)*Du - Dp
    do j = g-1, Bs+g+2
        do i = g-1, Bs+g+2
            dummy(i,j)  = u(i,j)*rho(i,j)*u(i,j)
            dummy2(i,j) = v(i,j)*rho(i,j)*u(i,j)
        end do
    end do
    call diffx_c_opt( Bs, g, dx, dummy,  dummy3)
    call diffy_c_opt( Bs, g, dy, dummy2, dummy4)

    do j = g+1, Bs+g
        do i = g+1, Bs+g
            rhs(i,j,2) = ( rhs(i,j,2) - 0.5_rk * ( dummy3(i,j) + dummy4(i,j) ) ) * phi1_inv(i,j)
        end do
    end do

    ! RHS of  momentum equation for v
    do j = g-1, Bs+g+2
        do i = g-1, Bs+g+2
            dummy(i,j)  = u(i,j)*rho(i,j)*v(i,j)
            dummy2(i,j) = v(i,j)*rho(i,j)*v(i,j)
        end do
    end do
    call diffx_c_opt( Bs, g, dx, dummy,  dummy3)
    call diffy_c_opt( Bs, g, dy, dummy2, dummy4)

    do j = g+1, Bs+g
        do i = g+1, Bs+g
            rhs(i,j,3) = ( rhs(i,j,3) - 0.5_rk * ( dummy3(i,j) + dummy4(i,j) ) ) * phi1_inv(i,j)
        end do
    end do

    ! RHS of energy equation:  p_t = -gamma*div(U_tilde p) + gamm1 *U x grad(p)
    do j = g-1, Bs+g+2
        do i = g-1, Bs+g+2
            dummy(i,j)  = u(i,j)*p(i,j)
            dummy2(i,j) = v(i,j)*p(i,j)
        end do
    end do
    call diffx_c_opt( Bs, g, dx, dummy,  dummy3)
    call diffy_c_opt( Bs, g, dy, dummy2, dummy4)

    do j = g+1, Bs+g
        do i = g+1, Bs+g
            rhs(i,j,4) = rhs(i,j,4) - gamma_ * ( dummy3(i,j) + dummy4(i,j) )
        end do
    end do   

end subroutine RHS_2D_navier_stokes

!---------------------------------------------------------------------------------------------
!---------------------------------------------------------------------------------------------
!---------------------------------------------------------------------------------------------
!---------------------------------------------------------------------------------------------
!---------------------------------------------------------------------------------------------

subroutine  diffxy_c_opt( Bs, g, dx, dy, u, dudx, dudy)

    integer(kind=ik), intent(in)    :: g, Bs
    real(kind=rk), intent(in)       :: dx, dy
    real(kind=rk), intent(in)       :: u(Bs+2*g, Bs+2*g)
    real(kind=rk), intent(out)      :: dudx(Bs+2*g, Bs+2*g), dudy(Bs+2*g, Bs+2*g)

    integer                         :: i, j
    real(kind=rk)                   :: dx_inv, dy_inv

    ! - do not use all ghost nodes (note: use only two ghost nodes to get correct second derivatives)
    ! - no one sided stencils necessary 
    ! - write loops explicitly, 
    ! - use multiplication for dx
    ! - access array in column-major order

    dx_inv = 1.0_rk/(12.0_rk*dx)
    dy_inv = 1.0_rk/(12.0_rk*dy)

    do j = g-1, Bs+g+2
        do i = g-1, Bs+g+2
            dudx(i,j) = ( u(i-2,j) - 8.0_rk*u(i-1,j) + 8.0_rk*u(i+1,j) - u(i+2,j) ) * dx_inv
            dudy(i,j) = ( u(i,j-2) - 8.0_rk*u(i,j-1) + 8.0_rk*u(i,j+1) - u(i,j+2) ) * dy_inv
        end do
    end do

end subroutine diffxy_c_opt

subroutine  diffx_c_opt( Bs, g, dx, u, dudx)

    integer(kind=ik), intent(in)    :: g, Bs
    real(kind=rk), intent(in)       :: dx
    real(kind=rk), intent(in)       :: u(Bs+2*g, Bs+2*g)
    real(kind=rk), intent(out)      :: dudx(Bs+2*g, Bs+2*g)

    integer                         :: i, j
    real(kind=rk)                   :: dx_inv

    ! - do not use ghost nodes
    ! - no one sided stencils necessary 
    ! - write loops explicitly, 
    ! - use multiplication for dx
    ! - access array in column-major order

    dx_inv = 1.0_rk/(12.0_rk*dx)

    do j = g+1, Bs+g
        do i = g+1, Bs+g
            dudx(i,j) = ( u(i-2,j) - 8.0_rk*u(i-1,j) + 8.0_rk*u(i+1,j) - u(i+2,j) ) * dx_inv
        end do
    end do

end subroutine diffx_c_opt

subroutine  diffy_c_opt( Bs, g, dy, u, dudy)

    integer(kind=ik), intent(in)    :: g, Bs
    real(kind=rk), intent(in)       :: dy
    real(kind=rk), intent(in)       :: u(Bs+2*g, Bs+2*g)
    real(kind=rk), intent(out)      :: dudy(Bs+2*g, Bs+2*g)

    integer                         :: i, j
    real(kind=rk)                   :: dy_inv

    ! - do not use ghost nodes
    ! - no one sided stencils necessary 
    ! - write loops explicitly, 
    ! - use multiplication for dx
    ! - access array in column-major order

    dy_inv = 1.0_rk/(12.0_rk*dy)

    do j = g+1, Bs+g
        do i = g+1, Bs+g
            dudy(i,j) = ( u(i,j-2) - 8.0_rk*u(i,j-1) + 8.0_rk*u(i,j+1) - u(i,j+2) ) * dy_inv
        end do
    end do

end subroutine diffy_c_opt

!---------------------------------------------------------------------------------------------
!---------------------------------------------------------------------------------------------
! OLD stuff
!---------------------------------------------------------------------------------------------
!---------------------------------------------------------------------------------------------

subroutine grad_zentral(Bs, g, dx, dy, q, qx, qy)
    use module_params
    integer(kind=ik), intent(in)    :: g, Bs
    real(kind=rk), intent(in)       :: dx, dy
    real(kind=rk), intent(in)       :: q(Bs+2*g, Bs+2*g)
    real(kind=rk), intent(out)      :: qx(Bs+2*g, Bs+2*g)
    real(kind=rk), intent(out)      :: qy(Bs+2*g, Bs+2*g)

    !! XXX !!
    call diffx_c( Bs, g, dx, q, qx)

    !! YYY !!
    call diffy_c( Bs, g, dy, q, qy)

end subroutine grad_zentral

!---------------------------------------------------------------------------------------------

subroutine diff1x_zentral(Bs, g, dx, q, qx)
    use module_params
    integer(kind=ik), intent(in)    :: g, Bs
    real(kind=rk), intent(in)       :: dx
    real(kind=rk), intent(in)       :: q(Bs+2*g, Bs+2*g)
    real(kind=rk), intent(out)      :: qx(Bs+2*g, Bs+2*g)

    !! XXX !!
    call diffx_c( Bs, g, dx, q, qx)

end subroutine diff1x_zentral

!---------------------------------------------------------------------------------------------

subroutine diff1y_zentral(Bs, g, dy, q, qy)
    use module_params
    integer(kind=ik), intent(in)    :: g, Bs
    real(kind=rk), intent(in)       :: dy
    real(kind=rk), intent(in)       :: q(Bs+2*g, Bs+2*g)
    real(kind=rk), intent(out)      :: qy(Bs+2*g, Bs+2*g)

    !! XXX !!
    call diffy_c( Bs, g, dy, q, qy)

end subroutine diff1y_zentral

!---------------------------------------------------------------------------------------------

subroutine  diffx_c( Bs, g, dx, u, dudx)
    use module_params
    integer(kind=ik), intent(in)    :: g, Bs
    real(kind=rk), intent(in)       :: dx
    real(kind=rk), intent(in)       :: u(Bs+2*g, Bs+2*g)
    real(kind=rk), intent(out)      :: dudx(Bs+2*g, Bs+2*g)

    integer                         :: i, n

    n = size(u,1)

    !dudx(1,:) = ( u(n-1,:) - 8.0_rk*u(n,:) + 8.0_rk*u(2,:) - u(3,:) ) / (12.0_rk*dx)
    !dudx(2,:) = ( u(n,:)   - 8.0_rk*u(1,:) + 8.0_rk*u(3,:) - u(4,:) ) / (12.0_rk*dx)
    dudx(1,:) = ( u(2,:) - u(1,:) ) / (dx)
    dudx(2,:) = ( u(3,:) - u(1,:) ) / (2.0_rk*dx)

    forall ( i = 3:n-2 )
       dudx(i,:) = ( u(i-2,:) - 8.0_rk*u(i-1,:) + 8.0_rk*u(i+1,:) - u(i+2,:) ) / (12.0_rk*dx)
    end forall

    !dudx(n-1,:) = ( u(n-3,:) - 8.0_rk*u(n-2,:) + 8.0_rk*u(n,:) - u(1,:) ) / (12.0_rk*dx)
    !dudx(n,:)   = ( u(n-2,:) - 8.0_rk*u(n-1,:) + 8.0_rk*u(1,:) - u(2,:) ) / (12.0_rk*dx)
    dudx(n-1,:) = ( u(n,:) - u(n-2,:) ) / (2.0_rk*dx)
    dudx(n,:)   = ( u(n,:) - u(n-1,:) ) / (dx)

end subroutine diffx_c


subroutine  diffy_c( Bs, g, dy, u, dudy)
    use module_params
    integer(kind=ik), intent(in)    :: g, Bs
    real(kind=rk), intent(in)       :: dy
    real(kind=rk), intent(in)       :: u(Bs+2*g, Bs+2*g)
    real(kind=rk), intent(out)      :: dudy(Bs+2*g, Bs+2*g)

    integer                         :: i, n

    n = size(u,1)

    !dudy(:,1) = ( u(:,n-1) - 8.0_rk*u(:,n) + 8.0_rk*u(:,2) - u(:,3) ) / (12.0_rk*dy)
    !dudy(:,2) = ( u(:,n)   - 8.0_rk*u(:,1) + 8.0_rk*u(:,3) - u(:,4) ) / (12.0_rk*dy)
    dudy(:,1) = ( u(:,2) - u(:,1) ) / (dy)
    dudy(:,2) = ( u(:,3) - u(:,1) ) / (2.0_rk*dy)

    forall ( i = 3:n-2 )
       dudy(:,i) = ( u(:,i-2) - 8.0_rk*u(:,i-1) + 8.0_rk*u(:,i+1) - u(:,i+2) ) / (12.0_rk*dy)
    end forall

    !dudy(:,n-1) = ( u(:,n-3) - 8.0_rk*u(:,n-2) + 8.0_rk*u(:,n) - u(:,1) ) / (12.0_rk*dy)
    !dudy(:,n)   = ( u(:,n-2) - 8.0_rk*u(:,n-1) + 8.0_rk*u(:,1) - u(:,2) ) / (12.0_rk*dy)
    dudy(:,n-1) = ( u(:,n) - u(:,n-2) ) / (2.0_rk*dy)
    dudy(:,n)   = ( u(:,n) - u(:,n-1) ) / (dy)

end subroutine diffy_c


