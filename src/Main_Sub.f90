! https://github.com/MichaelSiehl/Atomic_Subroutines--Using_them_to_implement_a_bi-directional_synchronization

module Main_Sub
!
contains
!
!**********
!
subroutine Entry_Main_Sub
  !
  use OOOPimma_admImageManager
  !
  implicit none
  !
  call OOOPimma_Start (OOOPimmaImageManager_1) ! start the ImageManager on all images
  !
end subroutine Entry_Main_Sub
!
!**********
!
end module Main_Sub
