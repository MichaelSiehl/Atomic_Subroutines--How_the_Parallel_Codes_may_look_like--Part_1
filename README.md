# Atomic_Subroutines--How_the_Parallel_Codes_may_look_like--Part_1
Fortran 2008 coarray programming with unordered execution segments (user-defined ordering) - Atomic Subroutines: How the parallel logic codes may look like - Part 1

# Note
The content of this Github repository is still experimental.<br />

To my current understanding, the core solutions herein are very similar to the solution of the ABA problem with the Compare-And-Swap (CAS) hardware implementation for atomic operations on x86 computers. See the following links for a description of the ABA problem:<br />
https://jfdube.wordpress.com/2011/11/30/understanding-atomic-operations/<br />
https://en.wikipedia.org/wiki/Compare-and-swap<br />
https://en.wikipedia.org/wiki/ABA_problem<br />

Nevertheless, our solution for solving the ABA-style problems herein may differ somewhat from the hardware-related solutions: Instead, we use two simple programming techniques:<br />
(1)<br />
Compared to the ABA solution, we just use an ordinary integer scalar to store an integer-based enumeration value (this is similar to the appended increment counter of the ABA solution) together with the main atomic value (which I call 'additional atomic value' in the repository's source code): https://github.com/MichaelSiehl/Atomic_Subroutines--Using_Integers_Efficiently.<br />
Nevertheless, we do not use that programming technique directly to solve an ABA-style problem here, but merely to implement the sophisticated synchronization methods herein. (Also, the integer-based enumeration helps to make the parallel logic codes more readable, compared to a simple increment counter).<br />
(2)<br />
To prevent ABA-style problems herein, we use a simple array technique: https://github.com/MichaelSiehl/Atomic_Subroutines--Using_Coarray_Arrays_to_Allow_for_Safe_Remote_Communication:<br />
OpenCoarrays does allow to use remote atomic_define together with a single (scalar) array element of an integer array component (of a derived type coarray). (The 'remote' here is not supported by ifort 18 beta update 1 yet).<br />
Together with the above ABA-like solution, we can safely synchronize the value of each distinct (scalar) array element atomically.<br />
This might also be the promising solution for synchronizing whole integer arrays atomically later on. And if we can process whole integer arrays atomically (and since integer is a very general data type that can in principle be used to store other data types with it), there might be no restrictions for implementing even more sophisticated algorithms based entirely on atomics (and thus, with user-defined segment ordering).

# Overview
This GitHub repository contains a simple but working example program to restore segment ordering among a number of coarray images, using Fortran 2008 source code. The example program does run on 4 coarray images with unordered execution segments among all of them before segment order restoring starts. The example restores the segment ordering among images 2, 3, and 4. To do so, image 1 does execute parallel logic code that does initiate and control the restoring process among the other coarray images. There are several (atomic) synchronizations required, between image 1 and each of the other images resp.<br />
Nevertheless, the aim is less to show how such segment restoring can be done, but rather how such parallel logic codes, based on atomic subroutines, may look like in principle. As such, this GitHub repository contains only a first version, showing best how the parallel logic codes are working. Thus, the excerpts of the parallel logic codes shown here are more redundant than desired.

Please follow with the second part for a less redundant version of the parallel codes using a customized synchronization procedure: https://github.com/MichaelSiehl/Atomic_Subroutines--How_the_Parallel_Codes_may_look_like--Part_2

The src folder contains the complete code with additionally required files. The parallel logic codes shown here are all in the source code file OOOPimsc_admImageStatus_CA.f90.

# The Parallel Logic Code to initiate and control restoring of ordered execution segments (executed on image 1)
The following procedure 'OOOPimsc_SynchronizeTheInvolvedImages_CA' comprises all the required parallel logic codes that get executed on image 1 for initiating and controlling the segment synchronization (i.e. the restoring of ordered execution segments) among (and on) the remote images (2, 3, and 4 for this example).<br />

The procedure is divided into seven logical code sections (1)-(7):<br />
(1) initiate segment synchronization on the involved remote images<br />
(2) wait until all the involved remote image(s) do signal that they are in state WaitForSegmentSynchronization<br />
(3) set the involved remote images to state ContinueSegmentSynchronization<br />
(4) wait until all the involved remote image(s) do signal that they are in state SendetCurrentSegmentNumber<br />
(5) get the max segment (sync memory) count<br />
(6) initiate that the remote images do restore segment ordering<br />
(7) wait until all the involved remote image(s) do signal that they are in state FinishedSegmentSynchronization<br />

Code sections (2), (4), and (7) do contain a spin-wait loop synchronization each. For this example, these are the redundant code sections because we did not implement a customized snchronization procedure yet. (By comparing these code sections with those of the second version -in the other GitHub repository-, it may become more obvious how powerful customized synchronization procedures can be). <br />

Code sections (1), (3), and (6) do comprise calls to atomic_define each and do have counterpart spin-wait loop synchronizations, executed on the remote images.<br />

(Code section (5) is purely local and does not involve any interaction or data transfer with a remote image).<br />

(Access to atomic subroutines is encapsulated by calls of the procedures 'OOOPimscSAElement_atomic_intImageActivityFlag99_CA' (atomic_define) and 'OOOPimscGAElement_check_atomic_intImageActivityFlag99_CA' (atomic_ref)).<br />


```fortran
subroutine OOOPimsc_SynchronizeTheInvolvedImages_CA (Object_CA, intNumberOfImages,intA_RemoteImageNumbers)
  ! This routine is for stearing the execution segment synchronization (i.e. restoring of segment ordering)
  ! among a number of involved remote images. To do so, this routine gets executed on a separate coarray image
  ! (on image 1 with this example)
  !
  type (OOOPimsc_adtImageStatus_CA), codimension[*], intent (inout) :: Object_CA
  integer(OOOGglob_kint), intent (in) :: intNumberOfImages ! these are the number of involved remote images
  integer(OOOGglob_kint), dimension (intNumberOfImages), intent (in) :: intA_RemoteImageNumbers
  integer(OOOGglob_kint) :: status ! error status
  integer(OOOGglob_kint) :: intCount
  integer(OOOGglob_kint) :: intImageNumber
  integer(OOOGglob_kint) :: intImageActivityFlag
  integer(OOOGglob_kint) :: intSetFromImageNumber
  logical(OOOGglob_klog), dimension (intNumberOfImages) :: logA_CheckImageStates
  integer(OOOGglob_kint) :: intPackedEnumValue
  integer(OOOGglob_kint) :: intCurrentSegmentCount
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

# The Parallel Logic Codes to restore segment ordering (executed on images 2, 3, and 4 for this example)
The following parallel logic codes are responsible to restore segment ordering and get executed on those coarray images (i.e. the group of images) that shall experience the restoring.<br />

The first procedure will signal to the remote image (image 1) that this image is now in state 'WaitForSegmentSychronization'. That is the code executed between the logical code sections (1) and (2) of the OOOPimsc_SynchronizeTheInvolvedImages_CA procedure (see above):<br />

```fortran
subroutine OOOPimsc_Start_SegmentSynchronization_CA (Object_CA, intSetFromImageNumber)
  ! this routine starts the segment synchronization (restoring) on the involved inages
  ! (the involved images (not image 1) will execute this)
  ! (counterpart synchronization routine is IIimma_SYNC_CheckActivityFlag)
  type (OOOPimsc_adtImageStatus_CA), codimension[*], intent (inout) :: Object_CA
  integer(OOOGglob_kint), intent (in) :: intSetFromImageNumber ! this is the remote image number (image 1)
                                                               ! which initiated the synchronization
  integer(OOOGglob_kint) :: status = 0 ! error status
  integer(OOOGglob_kint) :: intImageActivityFlag
  integer(OOOGglob_kint) :: intPackedEnumValue
  integer(OOOGglob_kint) :: intRemoteImageNumber
  !
                                                                call OOOGglob_subSetProcedures &
                                                            ("OOOPimsc_Start_SegmentSynchronization_CA")
  !
  ! *********************************************************************
  ! start the segment synchronization (restoring) on the involved images:
  !
  intRemoteImageNumber = intSetFromImageNumber
  !
  intImageActivityFlag = OOOPimscEnum_ImageActivityFlag % WaitForSegmentSynchronization
  !
  ! pack the ImageActivityFlag together with this_image():
  call OOOPimsc_PackEnumValue_ImageActivityFlag (Object_CA, intImageActivityFlag, this_image(), intPackedEnumValue)
  !
  ! signal to the remote image (image 1) that this image is now in state 'WaitForSegmentSychronization':
  ! (counterpart synchronization routine is OOOPimsc_SynchronizeTheInvolvedImages_CA)
  call OOOPimscSAElement_atomic_intImageActivityFlag99_CA (Object_CA, intPackedEnumValue, &
                         intRemoteImageNumber, intArrayIndex = this_image(), logExecuteSyncMemory = .true.)
  !
  call OOOPimsc_WaitForSegmentSynchronization_CA (Object_CA, intSetFromImageNumber) ! (the routine is below)
  !
  call OOOPimsc_DoSegmentSynchronization_CA (Object_CA, intSetFromImageNumber) ! (the routine is below)
  !
  ! finish execution on the executing image (only for this example and to avoid an error stop statement
  ! to terminate execution):
  call OOOPimscSAElement_atomic_intImageActivityFlag99_CA (OOOPimscImageStatus_CA_1, OOOPimscEnum_ImageActivityFlag % &
                                    ExecutionFinished, this_image(), logExecuteSyncMemory = .false.)
  !
                                                                call OOOGglob_subResetProcedures
end subroutine OOOPimsc_Start_SegmentSynchronization_CA
```
The next procedure, OOOPimsc_WaitForSegmentSynchronization_CA, waits with further code execution until the ImageActivityFlag for this image is remotely set to state 'ContinueSegmentSynchronization'. This requires a spin-wait loop synchronization on each of the involved images. The spin-wait loop below is counterpart to logical code section (3) of the OOOPimsc_SynchronizeTheInvolvedImages_CA procedure (see above).<br />

Then, the procedure will transmit the SyncMemoryCount value (segment count) to the remote image 1. Image status turns into 'SendetCurrentSegmentNumber'. That code section is counterpart to logical code section (4) of the OOOPimsc_SynchronizeTheInvolvedImages_CA procedure.<br />

```fortran
subroutine OOOPimsc_WaitForSegmentSynchronization_CA (Object_CA, intSetFromImageNumber)
  ! Current image status is 'WaitForSegmentSynchronization',
  ! code execution on this image will be stopped until it is set to
  ! state 'ContinueSegmentSynchronization'.
  !
  ! Then, this routine will transmit the SyncMemoryCount value
  ! to the remote image with index 'SetFromImageNumber'.
  ! Image status turns into 'SendetCurrentSegmentNumber'.
  ! (the involved images (not image 1) will execute this)
  type (OOOPimsc_adtImageStatus_CA), codimension[*], intent (inout) :: Object_CA
  integer(OOOGglob_kint), intent (in) :: intSetFromImageNumber ! this is the remote image number (image 1)
                                                               ! which initiated the synchronization
  integer(OOOGglob_kint) :: status = 0 ! error status
  integer(OOOGglob_kint) :: intImageActivityFlag
  integer(OOOGglob_kint) :: intPackedEnumValue
  integer(OOOGglob_kint) :: intRemoteImageNumber
  integer(OOOGglob_kint) :: intSyncMemoryCount
  !
                                                                call OOOGglob_subSetProcedures &
                                                            ("OOOPimsc_WaitForSegmentSynchronization_CA")
  !
  intRemoteImageNumber = intSetFromImageNumber
  !**********************************************************************
  ! (1) wait until image state is remotely set to value ContinueSegmentSynchronization
  ! spin-wait loop synchronization:
  ! (conterpart routine is step 3 in OOOPimsc_SynchronizeTheInvolvedImages_CA)
  !
  do ! check the ImageActivityFlag in local PGAS memory permanently until it has
     !         value OOOPimscEnum_ImageActivityFlag % ContinueSegmentSynchronization
    if (OOOPimscGAElement_check_atomic_intImageActivityFlag99_CA (OOOPimscImageStatus_CA_1, &
                       OOOPimscEnum_ImageActivityFlag % ContinueSegmentSynchronization)) then
      !
      exit ! exit the loop if the remote image (1) has set this image to
           ! OOOPimscEnum_ImageActivityFlag % ContinueSegmentSynchronization
    end if
    !
  end do
  !
  !**********************************************************************
  ! (2) send the current intSyncMemoryCount on this image to the remote image:
  ! (conterpart synchronization routine is step 4 in OOOPimsc_SynchronizeTheInvolvedImages_CA)
  !
  intImageActivityFlag = OOOPimscEnum_ImageActivityFlag % SendetCurrentSegmentNumber
  !
  ! pack the intImageActivityFlag together with the current segment number:
  ! (a) get the SyncMemoryCount on this image:
  call OOOPimscGAElement_atomic_intImageSyncMemoryCount99_CA (Object_CA, intSyncMemoryCount)
  ! (b) increment it by one because of the following call to OOOPimscSAElement_atomic_intImageActivityFlag99_CA
  !     (which does execute SYNC MEMORY)
  intSyncMemoryCount = intSyncMemoryCount + 1
  ! (c) pack the Enum value with the SyncMemoryCount value (segment number):
  call OOOPimsc_PackEnumValue_ImageActivityFlag (Object_CA, intImageActivityFlag, intSyncMemoryCount, intPackedEnumValue)
  !
  ! signal to the remote image (image 1) that this image is now in state 'SendetCurrentSegmentNumber'
  ! and transmit also the current SyncMemoryCount within the same packed enum value:
  call OOOPimscSAElement_atomic_intImageActivityFlag99_CA (Object_CA, intPackedEnumValue, &
                         intRemoteImageNumber, intArrayIndex = this_image(), logExecuteSyncMemory = .true.)
  !
                                                                call OOOGglob_subResetProcedures
end subroutine OOOPimsc_WaitForSegmentSynchronization_CA

```
The next procedure, OOOPimsc_DoSegmentSynchronization_CA, waits with further code execution until the ImageActivityFlag for this image is remotely set to state 'DoSegmentSynchronization'. This requires another spin-wait loop synchronization on each of the involved images. The spin-wait loop below is counterpart to logical code section (6) of the OOOPimsc_SynchronizeTheInvolvedImages_CA procedure (see above).<br />

Then, the code does restore the segment ordering for the executing image.<br />

Finally, the procedure will send the current SyncMemoryCount on this image to the remote image 1. Image status turns into 'FinishedSegmentSynchronization'. That code section is counterpart to logical code section (7) of the OOOPimsc_SynchronizeTheInvolvedImages_CA procedure.<br />

```fortran
subroutine OOOPimsc_DoSegmentSynchronization_CA (Object_CA, intSetFromImageNumber)
  ! Current image status is 'SendetCurrentSegmentNumber',
  ! code execution on this image will be stopped until it is set to
  ! state 'DoSegmentSynchronization'.
  !
  ! Then, this routine will transmit the SyncMemoryCount value
  ! to the remote image with index 'SetFromImageNumber'.
  ! Image status turns into 'SendetCurrentSegmentNumber'.
  ! (the involved images (not image 1) will execute this)
  type (OOOPimsc_adtImageStatus_CA), codimension[*], intent (inout) :: Object_CA
  integer(OOOGglob_kint), intent (in) :: intSetFromImageNumber ! this is the remote image number (image 1)
                                                               ! which initiated the synchronization
  integer(OOOGglob_kint) :: status = 0 ! error status
  integer(OOOGglob_kint) :: intMaxSegmentCount
  integer(OOOGglob_kint) :: intNumberOfSyncMemoryStatementsToExecute
  integer(OOOGglob_kint) :: intImageActivityFlag
  integer(OOOGglob_kint) :: intPackedEnumValue
  integer(OOOGglob_kint) :: intRemoteImageNumber
  integer(OOOGglob_kint) :: intSyncMemoryCount
  integer(OOOGglob_kint) :: intCount
  !
                                                                call OOOGglob_subSetProcedures &
                                                            ("OOOPimsc_DoSegmentSynchronization_CA")
  !
  intRemoteImageNumber = intSetFromImageNumber
  !**********************************************************************
  ! (1) wait until image state is remotely set to value 'DoSegmentSynchronization'
  ! spin-wait loop synchronization:
  ! (conterpart routine is step 6 in OOOPimsc_SynchronizeTheInvolvedImages_CA)
  !
  do ! check the ImageActivityFlag in local PGAS memory permanently until it has
     !         value OOOPimscEnum_ImageActivityFlag % DoSegmentSynchronization
    if (OOOPimscGAElement_check_atomic_intImageActivityFlag99_CA (OOOPimscImageStatus_CA_1, &
                       OOOPimscEnum_ImageActivityFlag % DoSegmentSynchronization, &
                        intAdditionalAtomicValue = intMaxSegmentCount)) then
      !
      exit ! exit the loop if the remote image (1) has set this image to
           ! OOOPimscEnum_ImageActivityFlag % DoSegmentSynchronization
    end if
    !
  end do
  !**********************************************************************
  ! (2) restore the segment order (sync memory count) on the involved images (this image):
  !
  ! (a) get the SyncMemoryCount on this image:
  call OOOPimscGAElement_atomic_intImageSyncMemoryCount99_CA (Object_CA, intSyncMemoryCount)
  !
  ! (b) change the segment order only if this_image has a lower sync memory count as intMaxSegmentCount:
  if (intMaxSegmentCount .gt. intSyncMemoryCount) then
    intNumberOfSyncMemoryStatementsToExecute = intMaxSegmentCount - intSyncMemoryCount
    ! restore the segment order (among the involved images) for this image:
    do intCount = 1, intNumberOfSyncMemoryStatementsToExecute
      !
      call OOOPimsc_subSyncMemory (Object_CA) ! execute sync memory
      !
    end do
call OOOPimscGAElement_atomic_intImageSyncMemoryCount99_CA (Object_CA, intSyncMemoryCount)
write(*,*) 'segment order restored to value x on image y:',intSyncMemoryCount ,this_image()
  end if
  !
  !************************************************************************
  ! (3) send the current intSyncMemoryCount on this image to the remote image:
  ! (counterpart synchronization routine is step 7 in OOOPimsc_SynchronizeTheInvolvedImages_CA)
  !
  intImageActivityFlag = OOOPimscEnum_ImageActivityFlag % FinishedSegmentSynchronization
  ! pack the intImageActivityFlag together with the current segment number (sync memory count):
  ! (1) get the SyncMemoryCount on this image:
  call OOOPimscGAElement_atomic_intImageSyncMemoryCount99_CA (Object_CA, intSyncMemoryCount)
  ! (2) increment it by 1 because of the follow call to OOOPimscSAElement_atomic_intImageActivityFlag99_CA
  !     (which does execute SYNC MEMORY)
  intSyncMemoryCount = intSyncMemoryCount + 1
  ! (3) pack the enum value together with the SyncMemoryCount:
  call OOOPimsc_PackEnumValue_ImageActivityFlag (Object_CA, intImageActivityFlag, intSyncMemoryCount, intPackedEnumValue)
  !
  ! signal to the remote image (image 1) that this image is now in state 'FinishedSegmentSynchronization'
  call OOOPimscSAElement_atomic_intImageActivityFlag99_CA (Object_CA, intPackedEnumValue, &
                         intRemoteImageNumber, intArrayIndex = this_image(), logExecuteSyncMemory = .true.)
  !**********************************************************************
  !
                                                                call OOOGglob_subResetProcedures
end subroutine OOOPimsc_DoSegmentSynchronization_CA

```
