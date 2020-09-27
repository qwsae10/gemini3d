# Distributed under the OSI-approved BSD 3-Clause License.  See accompanying
# file Copyright.txt or https://cmake.org/licensing for details.

#[=======================================================================[.rst:
FindMETIS
-------
Michael Hirsch, Ph.D.

Finds the METIS library

Imported Targets
^^^^^^^^^^^^^^^^

METIS::METIS

Result Variables
^^^^^^^^^^^^^^^^

METIS_LIBRARIES
  libraries to be linked

METIS_INCLUDE_DIRS
  dirs to be included

#]=======================================================================]

set(METIS_LIBRARIES)

find_package(PkgConfig QUIET)
pkg_check_modules(pc_metis metis QUIET)

set(_to_find metis)
if(parallel IN_LIST METIS_FIND_COMPONENTS)
  list(PREPEND _to_find parmetis)
endif()

foreach(_lib ${_to_find})
  find_library(METIS_${_lib}_LIBRARY
    NAMES ${_lib}
    NAMES_PER_DIR
    PATH_SUFFIXES METIS lib libmetis
    PATHS ${pc_metis_LIBRARY_DIRS} ${pc_metis_LIBDIR}
    )

  list(APPEND METIS_LIBRARIES ${METIS_${_lib}_LIBRARY})
  mark_as_advanced(METIS_${_lib}_LIBRARY)
endforeach()

find_path(METIS_INCLUDE_DIR
          NAMES parmetis.h metis.h
          PATH_SUFFIXES METIS include
          PATHS ${pc_metis_INCLUDE_DIRS}
          )


include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(METIS
    REQUIRED_VARS METIS_LIBRARIES METIS_INCLUDE_DIR)

if(METIS_FOUND)
# need if _FOUND guard to allow project to autobuild; can't overwrite imported target even if bad
set(METIS_INCLUDE_DIRS ${METIS_INCLUDE_DIR})

if(NOT TARGET METIS::METIS)
  add_library(METIS::METIS INTERFACE IMPORTED)
  set_target_properties(METIS::METIS PROPERTIES
                        INTERFACE_LINK_LIBRARIES "${METIS_LIBRARIES}"
                        INTERFACE_INCLUDE_DIRECTORIES "${METIS_INCLUDE_DIR}"
                      )
endif()
endif(METIS_FOUND)

mark_as_advanced(METIS_INCLUDE_DIR METIS_LIBRARY)
