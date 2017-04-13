# Atomic_Subroutines--How_the_Parallel_Codes_may_look_like--Part_1
Fortran 2008 coarray programming with unordered execution segments (user-defined ordering) - Atomic Subroutines: How the parallel logic codes may look like - Part 1

# Overview
This GitHub repository contains a simple but working example program to restore segment ordering among a number of coarray images, using Fortran 2008 source code. The example program does run on 4 coarray images with unordered execution segments among all of them before segment order restoring starts. The example restores the segment ordering among images 2, 3, and 4. To do so, image 1 does execute parallel logic code that does initiate and control the restoring process among the other coarray images. There are several (atomic) synchronizations required, between image 1 and each of the other images resp.<br />
Nevertheless, the aim is less to show how such segment restoring can be done, but rather how parallel logic codes, based on atomic subroutines, may look like in principle. As such, this GitHub repository is only the first part, showing best how the parallel logic code is working. Therefore, the following excerpts of the parallel logic codes are more redundant than desired.

Please follow with the second part for a less redundant version of the parallel code using a customized synchronization procedure: https://github.com/MichaelSiehl/Atomic_Subroutines--How_the_Parallel_Codes_may_look_like--Part_2
