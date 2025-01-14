# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.

#[=======================================================================[.rst:

FindHDF5
---------

by Michael Hirsch www.scivision.dev

Finds HDF5 library for C, CXX, Fortran. Serial or parallel HDF5.


Result Variables
^^^^^^^^^^^^^^^^

``HDF5_FOUND``
  HDF5 libraries were found

``HDF5_INCLUDE_DIRS``
  HDF5 include directory

``HDF5_LIBRARIES``
  HDF5 library files

``HDF5_<lang>_COMPILER_EXECUTABLE``
  wrapper compiler for HDF5

Components
==========

``C``
  C is normally available for all HDF5 library installs

``CXX``
  C++ is an optional feature that not all HDF5 library installs are built with

``Fortran``
  Fortran is an optional feature that not all HDF5 library installs are built with

``parallel``
  checks that the optional MPI parallel HDF5 layer is enabled

``HL``
  always implied and silently accepted to keep compatibility with factory FindHDF5.cmake


Targets
^^^^^^^

``HDF5::HDF5``
  HDF5 Imported Target
#]=======================================================================]

include(CheckSymbolExists)
include(CheckCSourceCompiles)
include(CheckFortranSourceCompiles)

function(detect_config)

if(Fortran IN_LIST HDF5_FIND_COMPONENTS AND NOT HDF5_Fortran_FOUND)
  return()
endif()

if(CXX IN_LIST HDF5_FIND_COMPONENTS AND NOT HDF5_CXX_FOUND)
  return()
endif()

set(CMAKE_REQUIRED_INCLUDES ${HDF5_C_INCLUDE_DIR})

find_file(h5_conf
  NAMES H5pubconf.h H5pubconf-64.h
  HINTS ${HDF5_C_INCLUDE_DIR}
  NO_DEFAULT_PATH
)

if(NOT h5_conf)
  set(HDF5_C_FOUND false PARENT_SCOPE)
  return()
endif()

# check HDF5 features that require link of external libraries.
check_symbol_exists(H5_HAVE_FILTER_SZIP ${h5_conf} hdf5_have_szip)
check_symbol_exists(H5_HAVE_FILTER_DEFLATE ${h5_conf} hdf5_have_zlib)

# Always check for HDF5 MPI support because HDF5 link fails if MPI is linked into HDF5.
check_symbol_exists(H5_HAVE_PARALLEL ${h5_conf} HDF5_IS_PARALLEL)

set(HDF5_parallel_FOUND false PARENT_SCOPE)

if(HDF5_IS_PARALLEL)
  set(mpi_comp C)
  if(Fortran IN_LIST HDF5_FIND_COMPONENTS)
    list(APPEND mpi_comp Fortran)
  endif()

  find_package(MPI COMPONENTS ${mpi_comp})
  if(MPI_FOUND)
    set(HDF5_parallel_FOUND true PARENT_SCOPE)
  endif()
endif()

# get version
# from CMake/Modules/FindHDF5.cmake
file(STRINGS ${h5_conf} _def
REGEX "^[ \t]*#[ \t]*define[ \t]+H5_VERSION[ \t]+" )
if( "${_def}" MATCHES
"H5_VERSION[ \t]+\"([0-9]+\\.[0-9]+\\.[0-9]+)(-patch([0-9]+))?\"" )
  set(HDF5_VERSION "${CMAKE_MATCH_1}" )
  if( CMAKE_MATCH_3 )
    set(HDF5_VERSION ${HDF5_VERSION}.${CMAKE_MATCH_3})
  endif()

  set(HDF5_VERSION ${HDF5_VERSION} PARENT_SCOPE)
endif()

# avoid picking up incompatible zlib over the desired zlib
get_filename_component(_hint ${HDF5_C_LIBRARY} DIRECTORY)
if(NOT ZLIB_ROOT)
  set(ZLIB_ROOT "${HDF5_ROOT};${_hint}/..;${_hint}/../..")
endif()
if(NOT SZIP_ROOT)
  set(SZIP_ROOT "${ZLIB_ROOT}")
endif()

if(hdf5_have_zlib)
  find_package(ZLIB)

  if(hdf5_have_szip)
    # Szip even though not used by default.
    # If system HDF5 dynamically links libhdf5 with szip, our builds will fail if we don't also link szip.
    # however, we don't require SZIP for this case as other HDF5 libraries may statically link SZIP.
    find_package(SZIP)
    list(APPEND CMAKE_REQUIRED_LIBRARIES SZIP::SZIP)
  endif()

  list(APPEND CMAKE_REQUIRED_LIBRARIES ZLIB::ZLIB)
endif()

list(APPEND CMAKE_REQUIRED_LIBRARIES ${CMAKE_DL_LIBS})

set(THREADS_PREFER_PTHREAD_FLAG true)
find_package(Threads)
if(Threads_FOUND)
  list(APPEND CMAKE_REQUIRED_LIBRARIES Threads::Threads)
endif()

if(UNIX)
  list(APPEND CMAKE_REQUIRED_LIBRARIES m)
endif()

set(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES} PARENT_SCOPE)

endfunction(detect_config)


function(find_hdf5_fortran)
# NOTE: the "lib*" are for Windows Intel compiler, even for self-built HDF5.
# CMake won't look for lib prefix automatically.
set(_names hdf5_fortran libhdf5_fortran)
set(_hl_names hdf5_hl_fortran hdf5hl_fortran libhdf5_hl_fortran libhdf5hl_fortran)
set(wrapper_names h5fc h5fc-64)
if(parallel IN_LIST HDF5_FIND_COMPONENTS)
  list(PREPEND _names hdf5_openmpi_fortran hdf5_mpich_fortran)
  list(PREPEND _hl_names hdf5_openmpihl_fortran hdf5_mpichhl_fortran)
  set(wrapper_names h5pfc h5pfc.openmpi h5pfc.mpich)
endif()

find_program(HDF5_Fortran_COMPILER_EXECUTABLE
  NAMES ${wrapper_names}
)

find_library(HDF5_Fortran_LIBRARY
  NAMES ${_names}
  HINTS ${pc_hdf5_LIBRARY_DIRS} ${pc_hdf5_LIBDIR}
  PATH_SUFFIXES ${_lsuf}
  NAMES_PER_DIR
  DOC "HDF5 Fortran API")

find_library(HDF5_Fortran_HL_LIBRARY
  NAMES ${_hl_names}
  HINTS ${pc_hdf5_LIBRARY_DIRS} ${pc_hdf5_LIBDIR}
  PATH_SUFFIXES ${_lsuf}
  NAMES_PER_DIR
  DOC "HDF5 Fortran HL high-level API")
if(NOT (HDF5_Fortran_LIBRARY AND HDF5_Fortran_HL_LIBRARY))
  return()
endif()

# not all platforms have this stub
find_library(HDF5_Fortran_HL_stub
  NAMES hdf5_hl_f90cstub libhdf5_hl_f90cstub
  HINTS ${pc_hdf5_LIBRARY_DIRS} ${pc_hdf5_LIBDIR}
  PATH_SUFFIXES ${_lsuf}
  NAMES_PER_DIR
  DOC "Fortran C HL interface, not all HDF5 implementations have/need this")
find_library(HDF5_Fortran_stub
  NAMES hdf5_f90cstub libhdf5_f90cstub
  HINTS ${pc_hdf5_LIBRARY_DIRS} ${pc_hdf5_LIBDIR}
  PATH_SUFFIXES ${_lsuf}
  NAMES_PER_DIR
  DOC "Fortran C interface, not all HDF5 implementations have/need this")

set(HDF5_Fortran_LIBRARIES ${HDF5_Fortran_HL_LIBRARY} ${HDF5_Fortran_LIBRARY})
if(HDF5_Fortran_HL_stub AND HDF5_Fortran_stub)
list(APPEND HDF5_Fortran_LIBRARIES ${HDF5_Fortran_HL_stub} ${HDF5_Fortran_stub})
endif()

find_path(HDF5_Fortran_INCLUDE_DIR
  NAMES hdf5.mod
  HINTS ${pc_hdf5_INCLUDE_DIRS}
  PATH_SUFFIXES ${_msuf}
  PATHS /usr/lib64
  DOC "HDF5 Fortran modules")
  # CentOS: /usr/lib64/gfortran/modules/hdf5.mod
if(NOT HDF5_Fortran_INCLUDE_DIR)
  return()
endif()

set(HDF5_Fortran_LIBRARIES ${HDF5_Fortran_LIBRARIES} PARENT_SCOPE)
set(HDF5_Fortran_INCLUDE_DIR ${HDF5_Fortran_INCLUDE_DIR} PARENT_SCOPE)
set(HDF5_Fortran_FOUND true PARENT_SCOPE)
set(HDF5_HL_FOUND true PARENT_SCOPE)

endfunction(find_hdf5_fortran)


function(find_hdf5_cxx)

find_program(HDF5_CXX_COMPILER_EXECUTABLE
  NAMES h5c++ h5c++-64
)

find_library(HDF5_CXX_LIBRARY
  NAMES hdf5_cpp libhdf5_cpp
  HINTS ${pc_hdf5_LIBRARY_DIRS} ${pc_hdf5_LIBDIR}
  PATH_SUFFIXES ${_lsuf}
  NAMES_PER_DIR
  DOC "HDF5 C++ API")
find_library(HDF5_CXX_HL_LIBRARY
  NAMES hdf5_hl_cpp libhdf5_hl_cpp
  HINTS ${pc_hdf5_LIBRARY_DIRS} ${pc_hdf5_LIBDIR}
  PATH_SUFFIXES ${_lsuf}
  NAMES_PER_DIR
  DOC "HDF5 C++ high-level API")
if(NOT (HDF5_CXX_LIBRARY AND HDF5_CXX_HL_LIBRARY))
  return()
endif()

find_path(HDF5_CXX_INCLUDE_DIR
  NAMES hdf5.h
  HINTS ${pc_hdf5_INCLUDE_DIRS}
  PATH_SUFFIXES ${_psuf}
  DOC "HDF5 C header")

set(HDF5_CXX_LIBRARIES ${HDF5_CXX_HL_LIBRARY} ${HDF5_CXX_LIBRARY} PARENT_SCOPE)
set(HDF5_CXX_INCLUDE_DIR ${HDF5_CXX_INCLUDE_DIR} PARENT_SCOPE)
set(HDF5_CXX_FOUND true PARENT_SCOPE)
set(HDF5_HL_FOUND true PARENT_SCOPE)

endfunction(find_hdf5_cxx)


function(find_hdf5_c)

set(_names hdf5 libhdf5)
set(_hl_names hdf5_hl libhdf5_hl)
set(wrapper_names h5cc h5cc-64)
if(parallel IN_LIST HDF5_FIND_COMPONENTS)
  list(PREPEND _names hdf5_openmpi hdf5_mpich)
  list(PREPEND _hl_names hdf5_openmpi_hl hdf5_mpich_hl)
  set(wrapper_names h5pcc h5pcc.openmpi h5pcc.mpich)
endif()

find_program(HDF5_C_COMPILER_EXECUTABLE
  NAMES ${wrapper_names}
)

find_library(HDF5_C_LIBRARY
  NAMES ${_names}
  HINTS ${pc_hdf5_LIBRARY_DIRS} ${pc_hdf5_LIBDIR}
  PATH_SUFFIXES ${_lsuf}
  NAMES_PER_DIR
  DOC "HDF5 C library (necessary for all languages)")

find_library(HDF5_C_HL_LIBRARY
  NAMES ${_hl_names}
  HINTS ${pc_hdf5_LIBRARY_DIRS} ${pc_hdf5_LIBDIR}
  PATH_SUFFIXES ${_lsuf}
  NAMES_PER_DIR
  DOC "HDF5 C high level interface")
if(NOT (HDF5_C_HL_LIBRARY AND HDF5_C_LIBRARY))
  return()
endif()

find_path(HDF5_C_INCLUDE_DIR
  NAMES hdf5.h
  HINTS ${pc_hdf5_INCLUDE_DIRS}
  PATH_SUFFIXES ${_psuf}
  DOC "HDF5 C header")
if(NOT HDF5_C_INCLUDE_DIR)
  return()
endif()

set(HDF5_C_LIBRARIES ${HDF5_C_HL_LIBRARY} ${HDF5_C_LIBRARY} PARENT_SCOPE)
set(HDF5_C_INCLUDE_DIR ${HDF5_C_INCLUDE_DIR} PARENT_SCOPE)
set(HDF5_C_FOUND true PARENT_SCOPE)
set(HDF5_HL_FOUND true PARENT_SCOPE)

endfunction(find_hdf5_c)


function(check_hdf5_link)

if(NOT HDF5_C_FOUND)
  return()
endif()

list(PREPEND CMAKE_REQUIRED_LIBRARIES ${HDF5_C_LIBRARIES})
set(CMAKE_REQUIRED_INCLUDES ${HDF5_C_INCLUDE_DIR})

if(HDF5_parallel_FOUND)
  list(APPEND CMAKE_REQUIRED_LIBRARIES MPI::MPI_C)

  check_symbol_exists(H5Pset_fapl_mpio hdf5.h HAVE_H5Pset_fapl_mpio)
  if(NOT HAVE_H5Pset_fapl_mpio)
    return()
  endif()

  set(src [=[
  #include "hdf5.h"
  #include "mpi.h"

  int main(void){
  MPI_Init(NULL, NULL);

  hid_t plist_id = H5Pcreate(H5P_FILE_ACCESS);
  H5Pset_fapl_mpio(plist_id, MPI_COMM_WORLD, MPI_INFO_NULL);

  H5Pclose(plist_id);

  MPI_Finalize();

  return 0;
  }
  ]=])

else()
  set(src [=[
  #include "hdf5.h"

  int main(void){
  hid_t f = H5Fcreate("junk.h5", H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
  herr_t status = H5Fclose (f);
  return 0;}
  ]=])
endif(HDF5_parallel_FOUND)

check_c_source_compiles("${src}" HDF5_C_links)

if(NOT HDF5_C_links)
  return()
endif()



if(HDF5_Fortran_FOUND)

list(PREPEND CMAKE_REQUIRED_LIBRARIES ${HDF5_Fortran_LIBRARIES})
set(CMAKE_REQUIRED_INCLUDES ${HDF5_Fortran_INCLUDE_DIR} ${HDF5_C_INCLUDE_DIR})

if(HDF5_parallel_FOUND)
  list(APPEND CMAKE_REQUIRED_LIBRARIES MPI::MPI_Fortran)

  set(src "program test_fortran_mpi
  use hdf5
  use mpi

  integer :: ierr
  integer(HID_T) :: plist_id

  call mpi_init(ierr)

  call h5open_f(ierr)

  call h5pcreate_f(H5P_FILE_ACCESS_F, plist_id, ierr)
  call h5pset_fapl_mpio_f(plist_id, MPI_COMM_WORLD, MPI_INFO_NULL, ierr)

  call h5pclose_f(plist_id, ierr)

  call mpi_finalize(ierr)

  end program")
else()
  set(src "program test_minimal
  use hdf5, only : h5open_f, h5close_f
  use h5lt, only : h5ltmake_dataset_f
  implicit none
  integer :: i
  call h5open_f(i)
  call h5close_f(i)
  end program")
endif()

check_fortran_source_compiles(${src} HDF5_Fortran_links SRC_EXT f90)

if(NOT HDF5_Fortran_links)
  return()
endif()

endif(HDF5_Fortran_FOUND)


set(HDF5_links true PARENT_SCOPE)

endfunction(check_hdf5_link)

# === main program

set(CMAKE_REQUIRED_LIBRARIES)

# we don't use pkg-config names because some distros pkg-config for HDF5 is broken
# however at least the paths are often correct
find_package(PkgConfig)
if(NOT HDF5_FOUND)
  if(parallel IN_LIST HDF5_FIND_COMPONENTS)
    pkg_search_module(pc_hdf5 hdf5-openmpi hdf5-mpich hdf5)
  else()
    pkg_search_module(pc_hdf5 hdf5-serial hdf5)
  endif()
endif()

set(_lsuf hdf5)
if(parallel IN_LIST HDF5_FIND_COMPONENTS)
  list(PREPEND _lsuf openmpi/lib mpich/lib hdf5/openmpi hdf5/mpich)
else()
  list(PREPEND _lsuf hdf5/serial)
endif()

set(_psuf static ${_lsuf})
if(parallel IN_LIST HDF5_FIND_COMPONENTS)
  list(PREPEND _psuf openmpi-x86_64 mpich-x86_64)
endif()

set(_msuf ${_psuf})
if(CMAKE_Fortran_COMPILER_ID STREQUAL GNU)
  list(APPEND _msuf gfortran/modules)
  if(parallel IN_LIST HDF5_FIND_COMPONENTS)
    list(PREPEND _msuf gfortran/modules/openmpi gfortran/modules/mpich)
  endif()
endif()
# Not immediately clear the benefits of this, as we'd have to foreach()
# a priori names, kind of like we already do with find_library()
# find_package(hdf5 CONFIG)
# message(STATUS "hdf5 found ${hdf5_FOUND}")

if(Fortran IN_LIST HDF5_FIND_COMPONENTS)
  find_hdf5_fortran()
endif()

if(CXX IN_LIST HDF5_FIND_COMPONENTS)
  find_hdf5_cxx()
endif()

# C is always needed
find_hdf5_c()

# required libraries
if(HDF5_C_FOUND)
  detect_config()
endif(HDF5_C_FOUND)

# --- configure time checks
# these checks avoid messy, confusing errors at build time
check_hdf5_link()

set(CMAKE_REQUIRED_LIBRARIES)
set(CMAKE_REQUIRED_INCLUDES)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(HDF5
  REQUIRED_VARS HDF5_C_LIBRARIES HDF5_links
  VERSION_VAR HDF5_VERSION
  HANDLE_COMPONENTS)

if(HDF5_FOUND)
  set(HDF5_INCLUDE_DIRS ${HDF5_Fortran_INCLUDE_DIR} ${HDF5_CXX_INCLUDE_DIR} ${HDF5_C_INCLUDE_DIR})
  set(HDF5_LIBRARIES ${HDF5_Fortran_LIBRARIES} ${HDF5_CXX_LIBRARIES} ${HDF5_C_LIBRARIES})

  if(NOT TARGET HDF5::HDF5)
    add_library(HDF5::HDF5 INTERFACE IMPORTED)
    set_target_properties(HDF5::HDF5 PROPERTIES
      INTERFACE_LINK_LIBRARIES "${HDF5_LIBRARIES}"
      INTERFACE_INCLUDE_DIRECTORIES "${HDF5_INCLUDE_DIRS}")
    if(hdf5_have_zlib)
      target_link_libraries(HDF5::HDF5 INTERFACE ZLIB::ZLIB)
    endif()
    if(hdf5_have_szip)
      target_link_libraries(HDF5::HDF5 INTERFACE SZIP::SZIP)
    endif()

    if(Threads_FOUND)
      target_link_libraries(HDF5::HDF5 INTERFACE Threads::Threads)
    endif()

    target_link_libraries(HDF5::HDF5 INTERFACE ${CMAKE_DL_LIBS})

    if(UNIX)
      target_link_libraries(HDF5::HDF5 INTERFACE m)
    endif()
  endif()
endif()

mark_as_advanced(HDF5_Fortran_LIBRARY HDF5_Fortran_HL_LIBRARY
HDF5_C_LIBRARY HDF5_C_HL_LIBRARY
HDF5_CXX_LIBRARY HDF5_CXX_HL_LIBRARY
HDF5_C_INCLUDE_DIR HDF5_CXX_INCLUDE_DIR HDF5_Fortran_INCLUDE_DIR)
