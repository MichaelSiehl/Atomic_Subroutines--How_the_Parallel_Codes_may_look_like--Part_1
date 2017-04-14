# Atomic_Subroutines--How_the_Parallel_Codes_may_look_like--Part_1
Fortran 2008 coarray programming with unordered execution segments (user-defined ordering) - Atomic Subroutines: How the parallel logic codes may look like - Part 1

# Overview
This GitHub repository contains a simple but working example program to restore segment ordering among a number of coarray images, using Fortran 2008 source code. The example program does run on 4 coarray images with unordered execution segments among all of them before segment order restoring starts. The example restores the segment ordering among images 2, 3, and 4. To do so, image 1 does execute parallel logic code that does initiate and control the restoring process among the other coarray images. There are several (atomic) synchronizations required, between image 1 and each of the other images resp.<br />
Nevertheless, the aim is less to show how such segment restoring can be done, but rather how such parallel logic codes, based on atomic subroutines, may look like in principle. As such, this GitHub repository contains only a first version, showing best how the parallel logic code is working. Thus, the excerpts of the parallel logic codes shown here are more redundant than desired.

Please follow with the second part for a less redundant version of the parallel codes using a customized synchronization procedure: https://github.com/MichaelSiehl/Atomic_Subroutines--How_the_Parallel_Codes_may_look_like--Part_2

The src folder contains the complete code with additionally required files.

# The Parallel Logic Code to initiate and control restoring of ordered execution segments (executed on image 1)

```fortran
subroutine OOOPimsc_SynchronizeTheInvolvedImages_CA (Object_CA, intNumberOfImages,intA_RemoteImageNumbers)
  ! This routine is for stearing the execution segment synchronization (i.e. restoring of segment ordering)
  ! among a number of involved remote images. To do so, this routine gets executed on a separate coarray image
  ! (on image 1 with this example)
  !
  type (OOOPimsc_adtImageStatus_CA), codimension[*], volatile, intent (inout) :: Object_CA
  integer(OOOGglob_kint), intent (in) :: intNumberOfImages ! these are the number of involved remote images
  integer(OOOGglob_kint), dimension (intNumberOfImages), intent (in) :: intA_RemoteImageNumbers
  integer(OOOGglob_kint) :: status = 0 ! error status
  integer(OOOGglob_kint) :: intCount
  integer(OOOGglob_kint) :: intImageNumber
  integer(OOOGglob_kint) :: intImageActivityFlag
  integer(OOOGglob_kint) :: intSetFromImageNumber = 0
  logical(OOOGglob_klog), dimension (intNumberOfImages) :: logA_CheckImageStates
  integer(OOOGglob_kint) :: intPackedEnumValue
  integer(OOOGglob_kint) :: intCurrentSegmentCount = 0
  integer(OOOGglob_kint), dimension (1:intNumberOfImages, 1:2) :: intA_RemoteImageAndSegmentCounts
  integer(OOOGglob_kint) :: intMaxSegmentCount
  integer(OOOGglob_kint), dimension (1) :: intA_MaxSegmentCountLocation ! the array index
  integer(OOOGglob_kint), dimension (1) :: intA_ImageNumberWithMaxSegmentCount
  integer(OOOGglob_kint) :: intLocalSyncMemoryCount
  !
                                                                call OOOGglob_subSetProcedures &
                                                            ("OOOPimsc_SynchronizeTheInvolvedImages_CA")
  !
  !************************************************
  ! (1) initiate segment synchronization on the involved remote images:
  ! (counterpart synchronization routine is IIimma_SYNC_CheckActivityFlag)
  !
  intImageActivityFlag = OOOPimscEnum_ImageActivityFlag % InitiateSegmentSynchronization
  ! pack the ImageActivityFlag enumeration together with this_image():
  call OOOPimsc_PackEnumValue_ImageActivityFlag (Object_CA, intImageActivityFlag, this_image(), intPackedEnumValue)
  !
  call OOOPimsc_subSyncMemory (Object_CA) ! execute sync memory
  !
  do intCount = 1, intNumberOfImages
    !
    intImageNumber = intA_RemoteImageNumbers(intCount)
    if (intImageNumber .ne. this_image()) then ! (synchronization is only required between distinct images)
    ! initiate the segment synchronization on the involved remote images:
      ! send the packed enum value atomically to the remote image (intImageNumber):
      ! (counterpart synchronization routine is IIimma_SYNC_CheckActivityFlag)
      call OOOPimscSAElement_atomic_intImageActivityFlag99_CA (Object_CA, intPackedEnumValue, &
            intImageNumber, logExecuteSyncMemory = .false.) ! do not execute SYNC MEMORY
    end if
  end do
  !
  !************************************************
  ! (2) wait until all the involved remote image(s) do signal that they are in state WaitForSegmentSynchronization:
  ! (counterpart routine is OOOPimsc_Start_SegmentSynchronization_CA)
  !
  intImageActivityFlag = OOOPimscEnum_ImageActivityFlag % WaitForSegmentSynchronization
  ! initialize the array elements with .false.:
  logA_CheckImageStates = .false.
  !
  ! spin-wait loop synchronization:
  do
    do intCount = 1, intNumberOfImages
      !
      intImageNumber = intA_RemoteImageNumbers(intCount)
      if (intImageNumber .ne. this_image()) then ! (synchronization is only required between distinct images)
        if (.not. logA_CheckImageStates(intCount)) then ! check is only required if the remote image is not already
                                                        ! in state WaitForSegmentSynchronization:
          ! (counterpart routine is OOOPimsc_Start_SegmentSynchronization_CA):
          if (OOOPimscGAElement_check_atomic_intImageActivityFlag99_CA (OOOPimscImageStatus_CA_1, &
                           OOOPimscEnum_ImageActivityFlag % WaitForSegmentSynchronization, &
                           intArrayIndex = intImageNumber, intAdditionalAtomicValue = intSetFromImageNumber)) then
            logA_CheckImageStates(intCount) = .true. ! the remote image is in state WaitForSegmentSynchronization
          end if
        end if
      end if
    end do
    !
    if (all(logA_CheckImageStates)) exit ! exit the do loop if all involved remote images are in state
                                         ! WaitForSegmentSynchronization
    ! (be aware: due to the first if statement, this would be error prone in real world programming,
    !  but it is safe for this example program)
  end do
  !
  !**********************************************************************
  ! (3) set the involved remote images to state ContinueSegmentSynchronization:
  ! (counterpart synchronization routine is OOOPimsc_WaitForSegmentSynchronization_CA)
  !
  intImageActivityFlag = OOOPimscEnum_ImageActivityFlag % ContinueSegmentSynchronization
  ! pack the ImageActivityFlag enumeration together with this_image():
  call OOOPimsc_PackEnumValue_ImageActivityFlag (Object_CA, intImageActivityFlag, this_image(), intPackedEnumValue)
  !
  call OOOPimsc_subSyncMemory (Object_CA) ! execute sync memory
  !
  do intCount = 1, intNumberOfImages
    !
    intImageNumber = intA_RemoteImageNumbers(intCount)
    if (intImageNumber .ne. this_image()) then ! (synchronization is only required between distinct images)
    ! to continue the segment synchronization on the involved remote images:
      ! send the packed enum value atomically to the remote image (intImageNumber):
      call OOOPimscSAElement_atomic_intImageActivityFlag99_CA (Object_CA, intPackedEnumValue, &
            intImageNumber, logExecuteSyncMemory = .false.) ! do not execute SYNC MEMORY
    end if
  end do
  !
  !**********************************************************************
  ! (4) wait until all the involved remote image(s) do signal that they are in state SendetCurrentSegmentNumber:
  ! (counterpart routine is OOOPimsc_WaitForSegmentSynchronization_CA)
  !
  intImageActivityFlag = OOOPimscEnum_ImageActivityFlag % SendetCurrentSegmentNumber
  ! initialize the array elements with .false.:
  logA_CheckImageStates = .false.
  !
  ! spin-wait loop synchronization:
  do
    do intCount = 1, intNumberOfImages
      !
      intImageNumber = intA_RemoteImageNumbers(intCount)
      if (intImageNumber .ne. this_image()) then ! (synchronization is only required between distinct images)
        if (.not. logA_CheckImageStates(intCount)) then ! check is only required if the remote image is not already
                                                        ! in state SendetCurrentSegmentNumber:
          ! (counterpart routine is OOOPimsc_WaitForSegmentSynchronization_CA):
          if (OOOPimscGAElement_check_atomic_intImageActivityFlag99_CA (OOOPimscImageStatus_CA_1, &
                           OOOPimscEnum_ImageActivityFlag % SendetCurrentSegmentNumber, &
                           intArrayIndex = intImageNumber, intAdditionalAtomicValue = intCurrentSegmentCount)) then
            logA_CheckImageStates(intCount) = .true. ! the remote image is in state SendetCurrentSegmentNumber
            ! save the remote image number together with its currently held execution segment number:
            intA_RemoteImageAndSegmentCounts(intCount,1) = intImageNumber
            intA_RemoteImageAndSegmentCounts(intCount,2) = intCurrentSegmentCount
          end if
        end if
      end if
    end do
    !
    if (all(logA_CheckImageStates)) exit ! exit the do loop if all involved remote images are in state
                                         ! SendetCurrentSegmentNumber
    ! (be aware: due to the first if statement, this would be error prone in real world programming,
    !  but it is safe for this example program)
  end do
  !
  !**********************************************************************
  ! (5) get the max segment (sync memory) count (only the remote images):
  !
  intMaxSegmentCount = maxval(intA_RemoteImageAndSegmentCounts(:,2))
write(*,*)'MaxSegmentCount (MaxSyncMemoryCount): ', intMaxSegmentCount
  intA_MaxSegmentCountLocation = maxloc(intA_RemoteImageAndSegmentCounts(:,2))
  intA_ImageNumberWithMaxSegmentCount = intA_RemoteImageAndSegmentCounts (intA_MaxSegmentCountLocation,1)
write(*,*)'ImageNumberWithMaxSegmentCount: ', intA_ImageNumberWithMaxSegmentCount
  !
  !**********************************************************************
  ! (5a) get the segment (sync memory) count on this image (not required for this example program):
  call OOOPimscGAElement_atomic_intImageSyncMemoryCount99_CA (Object_CA, intLocalSyncMemoryCount)
  !
  !**********************************************************************
  ! (6) initiate that the remote images do restore segment ordering:
  ! (restore the segment order among the remote images only for this example)
  ! to do so, set the involved remote images to state DoSegmentSynchronization:
  ! (counterpart synchronization routine is OOOPimsc_DoSegmentSynchronization_CA)
  intImageActivityFlag = OOOPimscEnum_ImageActivityFlag % DoSegmentSynchronization
  !
  ! increment intMaxSegmentCount by 1 because the remote images will execute an
  ! additional sync memory statement when receiving the atomic value from the do loop below:
  intMaxSegmentCount = intMaxSegmentCount + 1
  ! pack the ImageActivityFlag enumeration together with the intMaxSegmentCount:
  call OOOPimsc_PackEnumValue_ImageActivityFlag (Object_CA, intImageActivityFlag, intMaxSegmentCount, intPackedEnumValue)
  !
  call OOOPimsc_subSyncMemory (Object_CA) ! execute sync memory
  !
  do intCount = 1, intNumberOfImages
    !
    intImageNumber = intA_RemoteImageNumbers(intCount)
    if (intImageNumber .ne. this_image()) then ! (synchronization is only required between distinct images)
    ! to execute the segment synchronization on the involved remote images:
      ! send the packed enum value atomically to the remote image (intImageNumber):
      call OOOPimscSAElement_atomic_intImageActivityFlag99_CA (Object_CA, intPackedEnumValue, &
            intImageNumber, logExecuteSyncMemory = .false.) ! do not execute SYNC MEMORY
    end if
  end do
  !
  !**********************************************************************
  ! (7) wait until all the involved remote image(s) do signal that they are in state FinishedSegmentSynchronization:
  ! (counterpart routine is OOOPimsc_DoSegmentSynchronization_CA)
  !
  intImageActivityFlag = OOOPimscEnum_ImageActivityFlag % FinishedSegmentSynchronization
  ! initialize the array elements with .false.:
  logA_CheckImageStates = .false.
  !
  ! spin-wait loop synchronization:
  do
    do intCount = 1, intNumberOfImages
      !
      intImageNumber = intA_RemoteImageNumbers(intCount)
      if (intImageNumber .ne. this_image()) then ! (synchronization is only required between distinct images)
        if (.not. logA_CheckImageStates(intCount)) then ! check is only required if the remote image is not already
                                                        ! in state SendetCurrentSegmentNumber:
          ! (counterpart routine is OOOPimsc_DoSegmentSynchronization_CA):
          if (OOOPimscGAElement_check_atomic_intImageActivityFlag99_CA (OOOPimscImageStatus_CA_1, &
                           OOOPimscEnum_ImageActivityFlag % FinishedSegmentSynchronization, &
                           intArrayIndex = intImageNumber, intAdditionalAtomicValue = intCurrentSegmentCount)) then
            logA_CheckImageStates(intCount) = .true. ! the remote image is in state FinishedSegmentSynchronization
            ! save the remote image number together with its restored execution segment number (sync memory count):
            intA_RemoteImageAndSegmentCounts(intCount,1) = intImageNumber
            intA_RemoteImageAndSegmentCounts(intCount,2) = intCurrentSegmentCount
write(*,*) 'remote image number and its CurrentSegmentCount:',intA_RemoteImageAndSegmentCounts(intCount,1:2)
          end if
        end if
      end if
    end do
    !
    if (all(logA_CheckImageStates)) exit ! exit the do loop if all involved remote images are in state
                                         ! SendetCurrentSegmentNumber
    ! (be aware: due to the first if statement, this would be error prone in real world programming,
    !  but it is safe for this example program)
  end do
  !
  !**********************************************************************
  !
                                                                call OOOGglob_subResetProcedures
end subroutine OOOPimsc_SynchronizeTheInvolvedImages_CA
```
