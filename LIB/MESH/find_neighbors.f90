!> neighbor codes: \n
!  ---------------
!> for imagination:
!!                   - 6-sided dice with '1'-side on top, '6'-side on bottom, '2'-side in front
!!                   - edge: boundary between two sides - use sides numbers for coding
!!                   - corner: between three sides - so use all three sides numbers
!!                   - block on higher/lower level: block shares face/edge and one unique corner,
!!                     so use this corner code in second part of neighbor code
!!
!! \image html neighborcode.svg "Neighborcode 3D" width=250
!!
!!faces:  '__1/___', '__2/___', '__3/___', '__4/___', '__5/___', '__6/___' \n
!! edges:  '_12/___', '_13/___', '_14/___', '_15/___'
!!         '_62/___', '_63/___', '_64/___', '_65/___'
!!         '_23/___', '_25/___', '_43/___', '_45/___' \n
!! corner: '123/___', '134/___', '145/___', '152/___'
!!         '623/___', '634/___', '645/___', '652/___' \n
!! \n
!! complete neighbor code array, 74 possible neighbor relations \n
!! neighbors = (/'__1/___', '__2/___', '__3/___', '__4/___', '__5/___', '__6/___', '_12/___', '_13/___', '_14/___', '_15/___',
!!               '_62/___', '_63/___', '_64/___', '_65/___', '_23/___', '_25/___', '_43/___', '_45/___', '123/___', '134/___',
!!               '145/___', '152/___', '623/___', '634/___', '645/___', '652/___', '__1/123', '__1/134', '__1/145', '__1/152',
!!               '__2/123', '__2/623', '__2/152', '__2/652', '__3/123', '__3/623', '__3/134', '__3/634', '__4/134', '__4/634',
!!               '__4/145', '__4/645', '__5/145', '__5/645', '__5/152', '__5/652', '__6/623', '__6/634', '__6/645', '__6/652',
!!               '_12/123', '_12/152', '_13/123', '_13/134', '_14/134', '_14/145', '_15/145', '_15/152', '_62/623', '_62/652',
!!               '_63/623', '_63/634', '_64/634', '_64/645', '_65/645', '_65/652', '_23/123', '_23/623', '_25/152', '_25/652',
!!               '_43/134', '_43/634', '_45/145', '_45/645' /) \n
! ********************************************************************************************
subroutine find_neighbor(params, hvyID_block, lgtID_block, Jmax, dir, error, n_domain)

    implicit none
    type (type_params), intent(in)      :: params                   !> user defined parameter structure
    integer(kind=ik), intent(in)        :: hvyID_block
    integer(kind=ik), intent(in)        :: lgtID_block
    integer(kind=ik), intent(in)        :: Jmax
    character(len=*), intent(in)        :: dir                      !> direction for neighbor search
    logical, intent(inout)              :: error
    integer(kind=2), intent(in)         :: n_domain(1:3)
    integer(kind=ik)                    :: neighborDirCode_sameLevel
    integer(kind=ik)                    :: neighborDirCode_coarserLevel, tcFinerAppendDigit(4)
    integer(kind=ik)                    :: neighborDirCode_finerLevel(4)
    integer(kind=ik)                    :: level
    integer(kind=ik)                    :: tcBlock(Jmax), tcNeighbor(Jmax), tcVirtual(Jmax)
    logical                             :: exists
    integer(kind=ik)                    :: lgtID_neighbor, tree_ID
    integer(kind=ik)                    :: k
    ! variable to show if there is a valid edge neighbor
    logical                             :: lvl_down_neighbor
    logical :: thereMustBeANeighbor

    tcBlock    = lgt_block( lgtID_block, 1:Jmax )
    level      = lgt_block( lgtID_block, Jmax + IDX_MESH_LVL )
    tree_ID    = lgt_block( lgtID_block, Jmax + IDX_TREE_ID )
    neighborDirCode_sameLevel     = -1
    neighborDirCode_coarserLevel  = -1
    neighborDirCode_finerLevel    = -1
    tcFinerAppendDigit            = -1

    ! not all blocks can have coarse neighbors.
    ! Consider:
    ! a c E E
    ! b d E E
    ! Then to the right, block b cannot have a coarser neighbor
    lvl_down_neighbor = .false.
    ! For the faces, we insist on finding neighbors (exception: symmetry conditions).
    ! for corners and edges, we do not- in the above example, block d does not
    ! have a neighbor in the top right corner.
    thereMustBeANeighbor = .false.


    ! 2D:
    !   faces: 1. same level: always one neighbor
    !          2. coarser: one neighbor, two possible neighbor codes
    !          3. finer: always two neighbors
    !   edges: 1. same level: always one neighbor
    !          2. coarser: one neighbor, possibly. Exists only if the coarser blocks corner coincides with the finer blocks corner.
    !          3. finer: always two neighbors




    ! set auxiliary variables
    select case(dir)
        case('__1/___')
            neighborDirCode_sameLevel    = 1
            thereMustBeANeighbor = .true.

            ! If the neighbor is coarser, then we have only one possible block, but
            ! the finer block (me) may be at four positions, which define the neighborhood code
            if ( tcBlock(level) == 4) then
                neighborDirCode_coarserLevel = 30
            elseif ( tcBlock(level) == 5) then
                neighborDirCode_coarserLevel = 29
            elseif ( tcBlock(level) == 6) then
                neighborDirCode_coarserLevel = 27
            elseif ( tcBlock(level) == 7) then
                neighborDirCode_coarserLevel = 28
            end if
            lvl_down_neighbor = .true.

            ! virtual treecodes, list_ids for neighbors on higher level
            tcFinerAppendDigit(1:4)  = (/ 4, 5, 6, 7 /)
            neighborDirCode_finerLevel(1:4) = (/ 30, 29, 27, 28 /)

        case('__2/___')
            neighborDirCode_sameLevel    = 2
            thereMustBeANeighbor = .true.

            ! If the neighbor is coarser, then we have only one possible block, but
            ! the finer block (me) may be at four positions, which define the neighborhood code
            if ( tcBlock(level) == 0) then
                neighborDirCode_coarserLevel = 34
            elseif ( tcBlock(level) == 2) then
                neighborDirCode_coarserLevel = 32
            elseif ( tcBlock(level) == 4) then
                neighborDirCode_coarserLevel = 33
            elseif ( tcBlock(level) == 6) then
                neighborDirCode_coarserLevel = 31
            end if
            lvl_down_neighbor = .true.

            ! virtual treecodes, list_ids for neighbors on higher level
            tcFinerAppendDigit(1:4)  = (/ 0, 2, 4, 6 /)
            neighborDirCode_finerLevel(1:4) = (/ 34, 32, 33, 31 /)

        case('__3/___')
            neighborDirCode_sameLevel    = 3
            thereMustBeANeighbor = .true.

            ! If the neighbor is coarser, then we have only one possible block, but
            ! the finer block (me) may be at four positions, which define the neighborhood code
            if ( tcBlock(level) == 2) then
                neighborDirCode_coarserLevel = 36
            elseif ( tcBlock(level) == 3) then
                neighborDirCode_coarserLevel = 38
            elseif ( tcBlock(level) == 6) then
                neighborDirCode_coarserLevel = 35
            elseif ( tcBlock(level) == 7) then
                neighborDirCode_coarserLevel = 37
            end if
            lvl_down_neighbor = .true.

            ! virtual treecodes, list_ids for neighbors on higher level
            tcFinerAppendDigit(1:4)  = (/ 2, 3, 6, 7 /)
            neighborDirCode_finerLevel(1:4) = (/ 36, 38, 35, 37 /)

        case('__4/___')
            neighborDirCode_sameLevel    = 4
            thereMustBeANeighbor = .true.

            ! If the neighbor is coarser, then we have only one possible block, but
            ! the finer block (me) may be at four positions, which define the neighborhood code
            if ( tcBlock(level) == 1) then
                neighborDirCode_coarserLevel = 42
            elseif ( tcBlock(level) == 3) then
                neighborDirCode_coarserLevel = 40
            elseif ( tcBlock(level) == 5) then
                neighborDirCode_coarserLevel = 41
            elseif ( tcBlock(level) == 7) then
                neighborDirCode_coarserLevel = 39
            end if
            lvl_down_neighbor = .true.

            ! virtual treecodes, list_ids for neighbors on higher level
            tcFinerAppendDigit(1:4)  = (/ 1, 3, 5, 7 /)
            neighborDirCode_finerLevel(1:4) = (/ 42, 40, 41, 39 /)

        case('__5/___')
            neighborDirCode_sameLevel    = 5
            thereMustBeANeighbor = .true.

            ! If the neighbor is coarser, then we have only one possible block, but
            ! the finer block (me) may be at four positions, which define the neighborhood code
            if ( tcBlock(level) == 0) then
                neighborDirCode_coarserLevel = 46
            elseif ( tcBlock(level) == 1) then
                neighborDirCode_coarserLevel = 44
            elseif ( tcBlock(level) == 4) then
                neighborDirCode_coarserLevel = 45
            elseif ( tcBlock(level) == 5) then
                neighborDirCode_coarserLevel = 43
            end if
            lvl_down_neighbor = .true.

            ! virtual treecodes, list_ids for neighbors on higher level
            tcFinerAppendDigit(1:4)  = (/ 0, 1, 4, 5 /)
            neighborDirCode_finerLevel(1:4) = (/ 46, 44, 45, 43 /)

        case('__6/___')
            neighborDirCode_sameLevel    = 6
            thereMustBeANeighbor = .true.

            ! If the neighbor is coarser, then we have only one possible block, but
            ! the finer block (me) may be at four positions, which define the neighborhood code
            if ( tcBlock(level) == 0) then
                neighborDirCode_coarserLevel = 50
            elseif ( tcBlock(level) == 1) then
                neighborDirCode_coarserLevel = 49
            elseif ( tcBlock(level) == 2) then
                neighborDirCode_coarserLevel = 47
            elseif ( tcBlock(level) == 3) then
                neighborDirCode_coarserLevel = 48
            end if
            lvl_down_neighbor = .true.

            ! virtual treecodes, list_ids for neighbors on higher level
            tcFinerAppendDigit(1:4)  = (/ 0, 1, 2, 3 /)
            neighborDirCode_finerLevel(1:4) = (/ 50, 49, 47, 48 /)

        case('_12/___')
            neighborDirCode_sameLevel    = 7

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 4) then
                neighborDirCode_coarserLevel = 52
            elseif ( tcBlock(level) == 6) then
                neighborDirCode_coarserLevel = 51
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 4) .or. (tcBlock( level ) == 6) )

            tcFinerAppendDigit(1:2)         = (/ 4, 6 /)
            neighborDirCode_finerLevel(1:2) = (/ 52, 51 /)

        case('_13/___')
            neighborDirCode_sameLevel    = 8

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 6) then
                neighborDirCode_coarserLevel = 53
            elseif ( tcBlock(level) == 7) then
                neighborDirCode_coarserLevel = 54
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 6) .or. (tcBlock( level ) == 7) )

            tcFinerAppendDigit(1:2)         = (/ 6, 7 /)
            neighborDirCode_finerLevel(1:2) = (/ 53, 54 /)

        case('_14/___')
            neighborDirCode_sameLevel    = 9

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 5) then
                neighborDirCode_coarserLevel = 56
            elseif ( tcBlock(level) == 7) then
                neighborDirCode_coarserLevel = 55
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 5) .or. (tcBlock( level ) == 7) )

            tcFinerAppendDigit(1:2)         = (/ 5, 7 /)
            neighborDirCode_finerLevel(1:2) = (/ 56, 55 /)

        case('_15/___')
            neighborDirCode_sameLevel    = 10

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 4) then
                neighborDirCode_coarserLevel = 58
            elseif ( tcBlock(level) == 5) then
                neighborDirCode_coarserLevel = 57
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 4) .or. (tcBlock( level ) == 5) )

            tcFinerAppendDigit(1:2)         = (/ 4, 5 /)
            neighborDirCode_finerLevel(1:2) = (/ 58, 57 /)

        case('_62/___')
            neighborDirCode_sameLevel    = 11

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 0) then
                neighborDirCode_coarserLevel = 60
            elseif ( tcBlock(level) == 2) then
                neighborDirCode_coarserLevel = 59
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 0) .or. (tcBlock( level ) == 2) )

            tcFinerAppendDigit(1:2)         = (/ 0, 2 /)
            neighborDirCode_finerLevel(1:2) = (/ 60, 59 /)

        case('_63/___')
            neighborDirCode_sameLevel    = 12

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 2) then
                neighborDirCode_coarserLevel = 61
            elseif ( tcBlock(level) == 3) then
                neighborDirCode_coarserLevel = 62
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 2) .or. (tcBlock( level ) == 3) )

            tcFinerAppendDigit(1:2)         = (/ 2, 3 /)
            neighborDirCode_finerLevel(1:2) = (/ 61, 62 /)

        case('_64/___')
            neighborDirCode_sameLevel    = 13

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 1) then
                neighborDirCode_coarserLevel = 64
            elseif ( tcBlock(level) == 3) then
                neighborDirCode_coarserLevel = 63
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 1) .or. (tcBlock( level ) == 3) )

            tcFinerAppendDigit(1:2)         = (/ 1, 3 /)
            neighborDirCode_finerLevel(1:2) = (/ 64, 63 /)

        case('_65/___')
            neighborDirCode_sameLevel    = 14

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 0) then
                neighborDirCode_coarserLevel = 66
            elseif ( tcBlock(level) == 1) then
                neighborDirCode_coarserLevel = 65
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 0) .or. (tcBlock( level ) == 1) )

            tcFinerAppendDigit(1:2)         = (/ 0, 1 /)
            neighborDirCode_finerLevel(1:2) = (/ 66, 65 /)

        case('_23/___')
            neighborDirCode_sameLevel    = 15

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 2) then
                neighborDirCode_coarserLevel = 68
            elseif ( tcBlock(level) == 6) then
                neighborDirCode_coarserLevel = 67
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 2) .or. (tcBlock( level ) == 6) )

            tcFinerAppendDigit(1:2)         = (/ 2, 6 /)
            neighborDirCode_finerLevel(1:2) = (/ 68, 67 /)

        case('_25/___')
            neighborDirCode_sameLevel    = 16

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 0) then
                neighborDirCode_coarserLevel = 70
            elseif ( tcBlock(level) == 4) then
                neighborDirCode_coarserLevel = 69
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 0) .or. (tcBlock( level ) == 4) )

            tcFinerAppendDigit(1:2)         = (/ 0, 4 /)
            neighborDirCode_finerLevel(1:2) = (/ 70, 69 /)

        case('_43/___')
            neighborDirCode_sameLevel    = 17

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 3) then
                neighborDirCode_coarserLevel = 72
            elseif ( tcBlock(level) == 7) then
                neighborDirCode_coarserLevel = 71
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 3) .or. (tcBlock( level ) == 7) )

            tcFinerAppendDigit(1:2)         = (/ 3, 7 /)
            neighborDirCode_finerLevel(1:2) = (/ 72, 71 /)

        case('_45/___')
            neighborDirCode_sameLevel    = 18

            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 1) then
                neighborDirCode_coarserLevel = 74
            elseif ( tcBlock(level) == 5) then
                neighborDirCode_coarserLevel = 73
            end if
            lvl_down_neighbor = ( (tcBlock( level ) == 1) .or. (tcBlock( level ) == 5) )

            tcFinerAppendDigit(1:2)         = (/ 1, 5 /)
            neighborDirCode_finerLevel(1:2) = (/ 74, 73 /)

        case('123/___')
            neighborDirCode_sameLevel      = 19
            neighborDirCode_coarserLevel   = 19
            neighborDirCode_finerLevel(1)  = 19
            tcFinerAppendDigit(1) = 6
            lvl_down_neighbor = ( tcBlock( level ) == 6 )

        case('134/___')
            neighborDirCode_sameLevel      = 20
            neighborDirCode_coarserLevel   = 20
            neighborDirCode_finerLevel(1)  = 20
            tcFinerAppendDigit(1) = 7
            lvl_down_neighbor = ( tcBlock( level ) == 7 )

        case('145/___')
            neighborDirCode_sameLevel      = 21
            neighborDirCode_coarserLevel   = 21
            neighborDirCode_finerLevel(1)  = 21
            tcFinerAppendDigit(1) = 5
            lvl_down_neighbor = ( tcBlock( level ) == 5 )

        case('152/___')
            neighborDirCode_sameLevel      = 22
            neighborDirCode_coarserLevel   = 22
            neighborDirCode_finerLevel(1)  = 22
            tcFinerAppendDigit(1) = 4
            lvl_down_neighbor = ( tcBlock( level ) == 4 )

        case('623/___')
            neighborDirCode_sameLevel      = 23
            neighborDirCode_coarserLevel   = 23
            neighborDirCode_finerLevel(1)  = 23
            tcFinerAppendDigit(1) = 2
            lvl_down_neighbor = ( tcBlock( level ) == 2 )

        case('634/___')
            neighborDirCode_sameLevel      = 24
            neighborDirCode_coarserLevel   = 24
            neighborDirCode_finerLevel(1)  = 24
            tcFinerAppendDigit(1) = 3
            lvl_down_neighbor = ( tcBlock( level ) == 3 )

        case('645/___')
            neighborDirCode_sameLevel      = 25
            neighborDirCode_coarserLevel   = 25
            neighborDirCode_finerLevel(1)  = 25
            tcFinerAppendDigit(1) = 1
            lvl_down_neighbor = ( tcBlock( level ) == 1 )

        case('652/___')
            neighborDirCode_sameLevel      = 26
            neighborDirCode_coarserLevel   = 26
            neighborDirCode_finerLevel(1)  = 26
            tcFinerAppendDigit(1) = 0
            lvl_down_neighbor = ( tcBlock( level ) == 0 )


        ! +~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~+
        !                 2D
        ! +~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~+
        case('_NE')
            neighborDirCode_sameLevel     = 5
            neighborDirCode_coarserLevel  = 5
            neighborDirCode_finerLevel(1) = 5
            tcFinerAppendDigit(1) = 1
            ! only sister block 1, 2 can have valid NE neighbor at one level down
            if ( (tcBlock( level ) == 1) .or. (tcBlock( level ) == 2) ) then
                lvl_down_neighbor = .true.
            end if

        case('_NW')
            neighborDirCode_sameLevel     = 6
            neighborDirCode_coarserLevel  = 6
            neighborDirCode_finerLevel(1) = 6
            tcFinerAppendDigit(1) = 0
            ! only sister block 0, 3 can have valid NW neighbor at one level down
            if ( (tcBlock( level ) == 0) .or. (tcBlock( level ) == 3) ) then
                lvl_down_neighbor = .true.
            end if

        case('_SE')
            neighborDirCode_sameLevel     = 7
            neighborDirCode_coarserLevel  = 7
            neighborDirCode_finerLevel(1) = 7
            tcFinerAppendDigit(1) = 3
            ! only sister block 0, 3 can have valid SE neighbor at one level down
            if ( (tcBlock( level ) == 0) .or. (tcBlock( level ) == 3) ) then
                lvl_down_neighbor = .true.
            end if

        case('_SW')
            neighborDirCode_sameLevel     = 8
            neighborDirCode_coarserLevel  = 8
            neighborDirCode_finerLevel(1) = 8
            tcFinerAppendDigit(1) = 2
            ! only sister block 1, 2 can have valid NE neighbor at one level down
            if ( (tcBlock( level ) == 1) .or. (tcBlock( level ) == 2) ) then
                lvl_down_neighbor = .true.
            end if

        case('__N')
            neighborDirCode_sameLevel = 1
            lvl_down_neighbor = .true.
            thereMustBeANeighbor = .true.
            ! virtual treecodes, list_ids for neighbors on higher level
            tcFinerAppendDigit(1:2)         = (/ 0, 1 /)
            neighborDirCode_finerLevel(1:2) = (/ 10,  9 /)
            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 0) then
                neighborDirCode_coarserLevel = 10
            elseif ( tcBlock(level) == 1) then
                neighborDirCode_coarserLevel = 9
            end if

        case('__E')
            neighborDirCode_sameLevel = 2
            lvl_down_neighbor = .true.
            thereMustBeANeighbor = .true.
            ! virtual treecodes for neighbors on higher level
            tcFinerAppendDigit(1:2)         = (/ 1, 3 /)
            neighborDirCode_finerLevel(1:2) = (/ 13, 14 /)
            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 1) then
                neighborDirCode_coarserLevel = 13
            elseif ( tcBlock(level) == 3) then
                neighborDirCode_coarserLevel = 14
            end if

        case('__S')
            neighborDirCode_sameLevel = 3
            lvl_down_neighbor = .true.
            thereMustBeANeighbor = .true.
            ! virtual treecodes for neighbors on higher level
            tcFinerAppendDigit(1:2)         = (/ 2, 3 /)
            neighborDirCode_finerLevel(1:2) = (/ 12, 11 /)
            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 3) then
                neighborDirCode_coarserLevel = 11
            elseif ( tcBlock(level) == 2) then
                neighborDirCode_coarserLevel = 12
            end if

        case('__W')
            neighborDirCode_sameLevel = 4
            lvl_down_neighbor = .true.
            thereMustBeANeighbor = .true.
            ! virtual treecodes for neighbors on higher level
            tcFinerAppendDigit(1:2)         = (/ 0, 2 /)
            neighborDirCode_finerLevel(1:2) = (/ 15, 16 /)
            ! neighbor code for coarser neighbors
            if ( tcBlock(level) == 0) then
                neighborDirCode_coarserLevel = 15
            elseif ( tcBlock(level) == 2) then
                neighborDirCode_coarserLevel = 16
            end if


        case default
            call abort(636300, "A weird error occured.")

    end select

    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ! 1) Check if we find a neighbor on the SAME LEVEL
    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ! calculate treecode for neighbor on same level
    call adjacent(tcBlock, tcNeighbor, dir, level, Jmax, params%dim)
    ! check if (hypothetical) neighbor exists and if so find its lgtID
    call doesBlockExist_tree(tcNeighbor, exists, lgtID_neighbor, tree_ID)

    if (exists) then
        ! we found the neighbor on the same level.
        hvy_neighbor( hvyID_block, neighborDirCode_sameLevel ) = lgtID_neighbor
        return
    endif

    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ! 2) Check if we find a neighbor on the COARSER LEVEL (if that is possible at all)
    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    if (lvl_down_neighbor) then
        ! We did not find the neighbor on the same level, and now check on the coarser level.
        ! Depending on my own treecode, I know what neighbor I am looking for, and I just set
        ! the last index to -1 = I go one level down (coarser)
        tcNeighbor( level ) = -1
        ! check if (hypothetical) neighbor exists and if so find its lgtID
        call doesBlockExist_tree(tcNeighbor, exists, lgtID_neighbor, tree_ID)

        if ( exists ) then
            ! neighbor is one level down (coarser)
            hvy_neighbor( hvyID_block, neighborDirCode_coarserLevel ) = lgtID_neighbor
            return
        endif
    endif


    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ! 3) Check if we find a neighbor on the FINER LEVEL
    !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ! Note: there are several neighbors possible on finer levels (up to four in 3D!)
    ! loop over all 4 possible neighbors
    if (level < Jmax) then
        do k = 1, 4
            if (tcFinerAppendDigit(k) /= -1) then
                ! first neighbor virtual treecode, one level up
                tcVirtual = tcBlock
                tcVirtual( level+1 ) = tcFinerAppendDigit(k)

                ! calculate treecode for neighbor on same level (virtual level)
                call adjacent(tcVirtual, tcNeighbor, dir, level+1, Jmax, params%dim)
                ! check if (hypothetical) neighbor exists and if so find its lgtID
                call doesBlockExist_tree(tcNeighbor, exists, lgtID_neighbor, tree_ID)

                if (exists) then
                    hvy_neighbor( hvyID_block, neighborDirCode_finerLevel(k) ) = lgtID_neighbor
                end if

                ! we did not find a neighbor. that may be a bad grid error, or simply, there is none
                ! because symmetry conditions are used.
                if (thereMustBeANeighbor) then
                    if ((.not. exists .and. ALL(params%periodic_BC)).or.(maxval(abs(n_domain))==0.and..not.exists)) then
                        write(*,*) dir, tcBlock, lvl_down_neighbor, level, ":", tcFinerAppendDigit
                        error = .true.
                    endif
                endif
            endif
        end do
    endif
end subroutine

! wrapper for adjacent_block_2D // adjacent_block_3D
subroutine adjacent(tcBlock, tcNeighbor, dir, level, Jmax, dim)
    use module_params
    implicit none
    integer(kind=ik), intent(in)        :: Jmax
    integer(kind=ik), intent(in)        :: level, dim
    integer(kind=ik), intent(in)        :: tcBlock(Jmax)   !> block treecode
    character(len=*), intent(in)        :: dir             !> direction for neighbor search
    integer(kind=ik), intent(out)       :: tcNeighbor(Jmax)!> neighbor treecode

    if (dim == 3) then
        call adjacent_block_3D(tcBlock, tcNeighbor, dir, level, Jmax)
    else
        call adjacent_block_2D(tcBlock, tcNeighbor, dir, level, Jmax)
    endif

end subroutine
