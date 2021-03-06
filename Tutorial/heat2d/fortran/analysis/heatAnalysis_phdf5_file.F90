program reader
   ! use adios_read_mod
    use HDF5
    use heat_print
    implicit none
    include 'mpif.h'

    character(len=256) :: filename, errmsg, tmp
    integer :: nproc          ! number of processors
    
    real*8, dimension(:,:),   allocatable :: T

    ! Offsets and sizes
    integer :: gndx, gndy
    integer*8, dimension(3) :: dims
    integer*8, dimension(3) :: maxdims
    integer*8, dimension(3) :: offset=0, readsize=1
    integer*8           :: sel  ! ADIOS selection object

    ! MPI variables
    integer :: group_comm
    integer :: rank
    integer :: ierr, nerrors

    integer :: ts=0   ! actual timestep
    integer :: i,j

    INTEGER(HID_T) :: file_id       ! File identifier
    INTEGER(HID_T) :: dset_id       ! Dataset identifier
    INTEGER(HID_T) :: dataspace     ! Dataspace identifier
    INTEGER(HID_T) :: memspace      ! Memory space identifier

    INTEGER(HID_T) :: fapl_id, dxpl_id;
    LOGICAL :: do_collective = .FALSE.

    call MPI_Init (ierr)
    call MPI_Comm_dup (MPI_COMM_WORLD, group_comm, ierr)
    call MPI_Comm_rank (MPI_COMM_WORLD, rank, ierr)
    call MPI_Comm_size (group_comm, nproc , ierr)
    call h5open_f(ierr)

    call processArgs()

    if (rank == 0) then
        print '(" Input file: ",a)', trim(filename)
    endif

    ! Open the file
    call h5pcreate_f(H5P_FILE_ACCESS_F, fapl_id, ierr)
  
    call h5pset_fapl_mpio_f(fapl_id, MPI_COMM_WORLD, MPI_INFO_NULL, ierr)

    call h5fopen_f (filename, H5F_ACC_RDONLY_F, file_id, ierr, access_prp = fapl_id)

    call h5pcreate_f(H5P_DATASET_XFER_F, dxpl_id, ierr)

    if (rank == 0) then
       write (*,*) "doing collective",     do_collective
    endif

    if (do_collective) then
        call h5pset_dxpl_mpio_f(dxpl_id, H5FD_MPIO_COLLECTIVE_F, ierr)
    endif

    ! Open the T dataset
    call h5dopen_f(file_id, "T", dset_id, ierr)

    ! Get the dimensions of T
    call h5dget_space_f(dset_id, dataspace, ierr)
    call h5sget_simple_extent_dims_f(dataspace, dims, maxdims, ierr)

    gndx = dims(1)
    gndy = dims(2)

    readsize(1) = gndx 
    readsize(2) = gndy / nproc
    readsize(3) = 1 ! Read one timestep

    offset(1)   = 0
    offset(2)   = rank * readsize(2)

    if (rank == nproc-1) then  ! last process should read all the rest of columns
        readsize(2) = gndy - readsize(2)*(nproc-1)
    endif
          
    allocate( T(readsize(1), readsize(2)) )

    
    do ts = 0,dims(3)-1

        if (rank == 0) then
            print '(" Read step       = ", i0)', ts
        endif

        offset(3) = ts

        ! Create a memory space for the partial read
        call h5screate_simple_f (3, readsize, memspace, ierr)

        call h5sselect_hyperslab_f(dataspace, H5S_SELECT_SET_F, offset, &
                                   readsize, ierr)
               
        call h5dread_f(dset_id, H5T_NATIVE_DOUBLE, T, readsize, ierr, &
                       memspace, dataspace, xfer_prp=dxpl_id)

        call print_array (T, offset, rank, ts)
    enddo
    
    call h5dclose_f(dset_id, ierr)

    call h5pclose_f(dxpl_id, ierr);

    call h5fclose_f(file_id, ierr)

    call h5pclose_f(fapl_id, ierr);

    call h5close_f(ierr)

    ! Terminate
    deallocate(T)
    call MPI_Finalize (ierr)

contains

    !!***************************
  subroutine usage()
    print *, "Usage: heatAnalysis_ph5  input [collecitve(c)]"
    print *, "input:  name of HDF5 input file [c]"
  end subroutine usage

!!***************************
  subroutine processArgs()

#ifndef __GFORTRAN__
#ifndef __GNUC__
    interface
         integer function iargc()
         end function iargc
    end interface
#endif
#endif

    integer :: numargs

    !! process arguments
    numargs = iargc()
    !print *,"Number of arguments:",numargs
    if ( numargs < 1 ) then
        call usage()
        call exit(1)
    endif

    call getarg(1, filename)

    if (numargs > 1) then
       call getarg(2, tmp) 
       if (tmp(1:1) == 'c') then
          do_collective = .TRUE.;
       endif        
    endif
    

  end subroutine processArgs
  end program reader  

