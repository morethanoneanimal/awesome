set(PROJECT_AWE_NAME awesome)

# If ${SOURCE_DIR} is a git repository VERSION is set to
# `git describe` later.
set(VERSION devel)

set(CODENAME "Technologic")

option(WITH_DBUS "build with D-BUS" ON)
option(GENERATE_MANPAGES "generate manpages" ON)
option(COMPRESS_MANPAGES "compress manpages" ON)
option(GENERATE_DOC "generate API documentation" ON)
if (GENERATE_DOC AND ENV{DO_COVERAGE})
    message(STATUS "Not generating API documentation with DO_COVERAGE")
endif()

# {{{ Endianness
include(TestBigEndian)
TEST_BIG_ENDIAN(AWESOME_IS_BIG_ENDIAN)
# }}}

# {{{ Find external utilities
macro(a_find_program var prg req)
    set(required ${req})
    find_program(${var} ${prg})
    if(NOT ${var})
        message(STATUS "${prg} not found.")
        if(required)
            message(FATAL_ERROR "${prg} is required to build awesome")
        endif()
    else()
        message(STATUS "${prg} -> ${${var}}")
    endif()
endmacro()

a_find_program(GIT_EXECUTABLE git FALSE)
# programs needed for man pages
a_find_program(ASCIIDOC_EXECUTABLE asciidoc FALSE)
a_find_program(XMLTO_EXECUTABLE xmlto FALSE)
a_find_program(GZIP_EXECUTABLE gzip FALSE)
# Lua documentation
if(GENERATE_DOC)
    a_find_program(LDOC_EXECUTABLE ldoc FALSE)
    if(NOT LDOC_EXECUTABLE)
        a_find_program(LDOC_EXECUTABLE ldoc.lua FALSE)
    endif()
    if(LDOC_EXECUTABLE)
        execute_process(COMMAND sh -c "${LDOC_EXECUTABLE} --sadly-ldoc-has-no-version-option 2>&1  | grep ' vs 1.4.5'"
                        OUTPUT_VARIABLE LDOC_VERSION_RESULT)
        if(NOT LDOC_VERSION_RESULT STREQUAL "")
            message(WARNING "Ignoring LDoc, because version 1.4.5 is known to be broken")
            unset(LDOC_EXECUTABLE CACHE)
        endif()
    endif()
    if(NOT LDOC_EXECUTABLE)
        message(STATUS "Not generating API documentation. Missing: ldoc.")
        set(GENERATE_DOC OFF)
    endif()
else()
    message(STATUS "Not generating API documentation.")
endif()
# theme graphics
a_find_program(CONVERT_EXECUTABLE convert TRUE)
# pkg-config
include(FindPkgConfig)
# lua
include(FindLua)
if (NOT LUA_FOUND)
    message(FATAL_ERROR
        "Could not find Lua. See the error above.\n"
        "You might want to hint it using the LUA_DIR environment variable, "
        "or set the LUA_INCLUDE_DIR / LUA_LIBRARY CMake variables.")
endif()
# }}}

# {{{ Check if documentation can be build
if(GENERATE_MANPAGES)
    if(NOT ASCIIDOC_EXECUTABLE OR NOT XMLTO_EXECUTABLE OR (COMPRESS_MANPAGES AND NOT GZIP_EXECUTABLE))
        if(NOT ASCIIDOC_EXECUTABLE)
            SET(missing "asciidoc")
        endif()
        if(NOT XMLTO_EXECUTABLE)
            SET(missing ${missing} " xmlto")
        endif()
        if(COMPRESS_MANPAGES AND NOT GZIP_EXECUTABLE)
            SET(missing ${missing} " gzip")
        endif()

        message(STATUS "Not generating manpages. Missing: " ${missing})
        set(GENERATE_MANPAGES OFF)
    endif()
endif()
# }}}

# {{{ Version stamp
if(OVERRIDE_VERSION)
    set(VERSION ${OVERRIDE_VERSION})
    message(STATUS "Using version from OVERRIDE_VERSION: ${VERSION}")
elseif(EXISTS ${SOURCE_DIR}/.git AND GIT_EXECUTABLE)
    # get current version
    execute_process(
        COMMAND ${GIT_EXECUTABLE} describe --dirty
        WORKING_DIRECTORY ${SOURCE_DIR}
        OUTPUT_VARIABLE VERSION
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    # File the build-utils/git-version-stamp.sh script will look into.
    set(VERSION_STAMP_FILE ${BUILD_DIR}/.version_stamp)
    file(WRITE ${VERSION_STAMP_FILE} ${VERSION})
    # create a version_stamp target later
    set(BUILD_FROM_GIT TRUE)
    message(STATUS "Using version from git: ${VERSION}")
elseif( EXISTS ${SOURCE_DIR}/.version_stamp )
    # get version from version stamp
    file(READ ${SOURCE_DIR}/.version_stamp VERSION)
    message(STATUS "Using version from ${SOURCE_DIR}/.version_stamp: ${VERSION}")
endif()
# }}}

# {{{ Required libraries
#
# this sets up:
# AWESOME_REQUIRED_LDFLAGS
# AWESOME_REQUIRED_INCLUDE_DIRS

# Use pkgconfig to get most of the libraries
pkg_check_modules(AWESOME_COMMON_REQUIRED REQUIRED
    xcb>=1.6)

set(AWESOME_DEPENDENCIES
    glib-2.0>=2.40
    gdk-pixbuf-2.0
    cairo
    x11
    xcb-cursor
    xcb-randr
    xcb-xtest
    xcb-xinerama
    xcb-shape
    xcb-util>=0.3.8
    xcb-keysyms>=0.3.4
    xcb-icccm>=0.3.8
    # NOTE: it's not clear what version is required, but 1.10 works at least.
    # See https://github.com/awesomeWM/awesome/pull/149#issuecomment-94208356.
    xcb-xkb
    xkbcommon
    xkbcommon-x11
    cairo-xcb
    libstartup-notification-1.0>=0.10
    xproto>=7.0.15
    libxdg-basedir>=1.0.0
    xcb-xrm
)

# Check the deps one by one
foreach(dependency ${AWESOME_DEPENDENCIES})
    unset(TMP_DEP_FOUND CACHE)
    pkg_check_modules(TMP_DEP REQUIRED ${dependency})

    if(NOT TMP_DEP_FOUND)
        message(FATAL_ERROR)
    endif()
endforeach()

# Do it again, but this time with the CFLAGS/LDFLAGS
pkg_check_modules(AWESOME_REQUIRED REQUIRED ${AWESOME_DEPENDENCIES})

macro(a_find_library variable library)
    find_library(${variable} ${library})
    if(NOT ${variable})
        message(FATAL_ERROR ${library} " library not found.")
    endif()
endmacro()

# Check for backtrace_symbols()
include(CheckFunctionExists)
check_function_exists(backtrace_symbols HAS_EXECINFO)
if(NOT HAS_EXECINFO)
    find_library(LIB_EXECINFO execinfo)
    if(LIB_EXECINFO)
        set(HAS_EXECINFO 1)
        set(AWESOME_REQUIRED_LDFLAGS
            ${AWESOME_REQUIRED_LDFLAGS}
            ${LIB_EXECINFO})
    endif()
endif()
if(HAS_EXECINFO)
    message(STATUS "checking for execinfo -- found")
else()
    message(STATUS "checking for execinfo -- not found")
endif()

# Do we need libm for round()?
check_function_exists(round HAS_ROUND_WITHOUT_LIBM)
if(NOT HAS_ROUND_WITHOUT_LIBM)
    SET(CMAKE_REQUIRED_LIBRARIES ${CMAKE_REQUIRED_LIBRARIES} m)
    set(AWESOME_REQUIRED_LDFLAGS ${AWESOME_REQUIRED_LDFLAGS} m)
    check_function_exists(round HAS_ROUND_WITH_LIBM)
    if(NOT HAS_ROUND_WITH_LIBM)
        message(FATAL_ERROR "Did not find round()")
    endif()
    message(STATUS "checking for round -- in libm")
else()
    message(STATUS "checking for round -- builtin")
endif()

set(AWESOME_REQUIRED_LDFLAGS
    ${AWESOME_COMMON_REQUIRED_LDFLAGS}
    ${AWESOME_REQUIRED_LDFLAGS}
    ${LUA_LIBRARIES}
    )

set(AWESOME_REQUIRED_INCLUDE_DIRS
    ${AWESOME_COMMON_REQUIRED_INCLUDE_DIRS}
    ${AWESOME_REQUIRED_INCLUDE_DIRS}
    ${LUA_INCLUDE_DIR})
# }}}

# {{{ Optional libraries
#
# this sets up:
# AWESOME_OPTIONAL_LDFLAGS
# AWESOME_OPTIONAL_INCLUDE_DIRS

if(WITH_DBUS)
    pkg_check_modules(DBUS dbus-1)
    if(DBUS_FOUND)
        set(AWESOME_OPTIONAL_LDFLAGS ${AWESOME_OPTIONAL_LDFLAGS} ${DBUS_LDFLAGS})
        set(AWESOME_OPTIONAL_INCLUDE_DIRS ${AWESOME_OPTIONAL_INCLUDE_DIRS} ${DBUS_INCLUDE_DIRS})
    else()
        set(WITH_DBUS OFF)
        message(STATUS "DBUS not found. Disabled.")
    endif()
endif()
# }}}

# {{{ Install path and configuration variables
#If a sysconfdir is specified, use it instead
#of the default configuration dir.
if(DEFINED SYSCONFDIR)
    set(SYSCONFDIR ${SYSCONFDIR} CACHE PATH "config directory")
else()
    set(SYSCONFDIR ${CMAKE_INSTALL_PREFIX}/etc CACHE PATH "config directory")
endif()

#If an XDG Config Dir is specificed, use it instead
#of the default XDG configuration dir.
if(DEFINED XDG_CONFIG_DIR)
    set(XDG_CONFIG_DIR ${XDG_CONFIG_DIR} CACHE PATH "xdg config directory")
else()
    set(XDG_CONFIG_DIR ${SYSCONFDIR}/xdg CACHE PATH "xdg config directory")
endif()

# setting AWESOME_DATA_PATH
if(DEFINED AWESOME_DATA_PATH)
    set(AWESOME_DATA_PATH ${AWESOME_DATA_PATH} CACHE PATH "awesome share directory")
else()
    set(AWESOME_DATA_PATH ${CMAKE_INSTALL_PREFIX}/share/${PROJECT_AWE_NAME} CACHE PATH "awesome share directory")
endif()

# setting AWESOME_DOC_PATH
if(DEFINED AWESOME_DOC_PATH)
    set(AWESOME_DOC_PATH ${AWESOME_DOC_PATH} CACHE PATH "awesome docs directory")
else()
    set(AWESOME_DOC_PATH ${CMAKE_INSTALL_PREFIX}/share/doc/${PROJECT_AWE_NAME} CACHE PATH "awesome docs directory")
endif()

# setting AWESOME_XSESSION_PATH
if(DEFINED AWESOME_XSESSION_PATH)
    set(AWESOME_XSESSION_PATH ${AWESOME_XSESSION_PATH} CACHE PATH "awesome xsessions directory")
else()
    set(AWESOME_XSESSION_PATH ${CMAKE_INSTALL_PREFIX}/share/xsessions CACHE PATH "awesome xsessions directory")
endif()

# set man path
if(DEFINED AWESOME_MAN_PATH)
   set(AWESOME_MAN_PATH ${AWESOME_MAN_PATH} CACHE PATH "awesome manpage directory")
else()
   set(AWESOME_MAN_PATH ${CMAKE_INSTALL_PREFIX}/share/man CACHE PATH "awesome manpage directory")
endif()

# Hide to avoid confusion
mark_as_advanced(CMAKE_INSTALL_CMAKE_INSTALL_PREFIX)

set(AWESOME_VERSION          ${VERSION})
set(AWESOME_RELEASE          ${CODENAME})
set(AWESOME_SYSCONFDIR       ${XDG_CONFIG_DIR}/${PROJECT_AWE_NAME})
set(AWESOME_LUA_LIB_PATH     ${AWESOME_DATA_PATH}/lib)
set(AWESOME_ICON_PATH        ${AWESOME_DATA_PATH}/icons)
set(AWESOME_THEMES_PATH      ${AWESOME_DATA_PATH}/themes)
# }}}

if(GENERATE_DOC)
    # Load the common documentation
    include(docs/load_ldoc.cmake)

    # Use `include`, rather than `add_subdirectory`, to keep the variables
    # The file is a valid CMakeLists.txt and can be executed directly if only
    # the image artefacts are needed.
    include(tests/examples/CMakeLists.txt)

    # Generate the widget lists
    include(docs/widget_lists.cmake)
endif()

# {{{ Configure files
file(GLOB awesome_base_c_configure_files RELATIVE ${SOURCE_DIR}
    ${SOURCE_DIR}/*.c
    ${SOURCE_DIR}/*.h)

file(GLOB awesome_c_configure_files RELATIVE ${SOURCE_DIR}
    ${SOURCE_DIR}/common/*.c
    ${SOURCE_DIR}/common/*.h
    ${SOURCE_DIR}/objects/*.c
    ${SOURCE_DIR}/objects/*.h)

file(GLOB_RECURSE awesome_lua_configure_files RELATIVE ${SOURCE_DIR}
    ${SOURCE_DIR}/lib/*.lua)

file(GLOB_RECURSE awesome_theme_configure_files RELATIVE ${SOURCE_DIR}
    ${SOURCE_DIR}/themes/*/*.lua)

set(AWESOME_CONFIGURE_FILES
    ${awesome_base_c_configure_files}
    ${awesome_theme_configure_files}
    config.h
    docs/config.ld
    awesome-version-internal.h)

foreach(file ${AWESOME_CONFIGURE_FILES})
    configure_file(${SOURCE_DIR}/${file}
                   ${BUILD_DIR}/${file}
                   ESCAPE_QUOTES
                   @ONLY)
endforeach()

set(AWESOME_CONFIGURE_COPYONLY_WITHCOV_FILES
    ${awesome_c_configure_files}
    ${awesome_lua_configure_files}
)

if(DO_COVERAGE)
    foreach(file ${AWESOME_CONFIGURE_COPYONLY_WITHCOV_FILES})
        configure_file(${SOURCE_DIR}/${file}
                    ${BUILD_DIR}/${file}
                    COPYONLY)
    endforeach()
else()
    foreach(file ${AWESOME_CONFIGURE_COPYONLY_WITHCOV_FILES})
        configure_file(${SOURCE_DIR}/${file}
                    ${BUILD_DIR}/${file}
                    ESCAPE_QUOTES
                    @ONLY)
    endforeach()
endif()

#}}}

# {{{ Generate some aggregated documentation from lua script

file(MAKE_DIRECTORY ${BUILD_DIR}/script_files/)

add_custom_command(
        OUTPUT ${BUILD_DIR}/docs/06-appearance.md
        COMMAND lua ${SOURCE_DIR}/docs/06-appearance.md.lua
        ${BUILD_DIR}/docs/06-appearance.md
        DEPENDS lgi-check
)

add_custom_command(
        OUTPUT ${BUILD_DIR}/awesomerc.lua ${BUILD_DIR}/docs/05-awesomerc.md
            ${BUILD_DIR}/script_files/rc.lua
        COMMAND lua ${SOURCE_DIR}/docs/05-awesomerc.md.lua
        ${BUILD_DIR}/docs/05-awesomerc.md ${SOURCE_DIR}/awesomerc.lua
        ${BUILD_DIR}/awesomerc.lua
        ${BUILD_DIR}/script_files/rc.lua
)

add_custom_command(
        OUTPUT ${BUILD_DIR}/script_files/theme.lua
        COMMAND lua ${SOURCE_DIR}/docs/sample_theme.lua ${BUILD_DIR}/script_files/
)

# Create a target for the auto-generated awesomerc.lua and other files
add_custom_target(generate_awesomerc DEPENDS
    ${BUILD_DIR}/awesomerc.lua
    ${BUILD_DIR}/script_files/theme.lua
    ${BUILD_DIR}/script_files/rc.lua
    ${SOURCE_DIR}/awesomerc.lua
    ${BUILD_DIR}/docs/06-appearance.md
    ${SOURCE_DIR}/docs/05-awesomerc.md.lua
    ${SOURCE_DIR}/docs/sample_theme.lua
    ${SOURCE_DIR}/docs/sample_files.lua
    ${SOURCE_DIR}/awesomerc.lua
)


#}}}

# {{{ Copy additional files
file(GLOB awesome_md_docs RELATIVE ${SOURCE_DIR}
    ${SOURCE_DIR}/docs/*.md)
set(AWESOME_ADDITIONAL_FILES
    ${awesome_md_docs})

foreach(file ${AWESOME_ADDITIONAL_FILES})
    configure_file(${SOURCE_DIR}/${file}
                   ${BUILD_DIR}/${file}
                   @ONLY)
endforeach()
#}}}

# vim: filetype=cmake:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:textwidth=80:foldmethod=marker
