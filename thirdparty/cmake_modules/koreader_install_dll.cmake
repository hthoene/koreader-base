# Install a DLL, given its import library.
#
# Usage: cmake -DDLLTOOL=… -DOBJCOPY=… -DIMPLIB=… -DSTAGING_DIR=… -DDESTINATION=… [-DKEEP_DEBUG=1] -P koreader_install_dll.cmake

foreach(VAR DLLTOOL OBJCOPY IMPLIB STAGING_DIR DESTINATION)
    if(NOT DEFINED ${VAR})
        message(FATAL_ERROR "${VAR} variable not defined!")
    endif()
endforeach()

execute_process(
    COMMAND ${DLLTOOL} --identify ${IMPLIB}
    OUTPUT_VARIABLE DLL
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE RET
)
if(NOT RET EQUAL 0 OR DLL STREQUAL "")
    message(FATAL_ERROR "could not identify DLL name from import library: ${IMPLIB}")
endif()

# NOTE: some projects don't install their DLL (missing `RUNTIME DESTINATION`),
# hence the fallback to the current directory (the project's build directory).
set(SRC)
foreach(DIR ${STAGING_DIR}/bin ${STAGING_DIR}/lib ${CMAKE_CURRENT_BINARY_DIR})
    if(EXISTS ${DIR}/${DLL})
        set(SRC ${DIR}/${DLL})
        break()
    endif()
endforeach()
if(NOT SRC)
    message(FATAL_ERROR "could not find ${DLL} (from import library: ${IMPLIB})")
endif()

function(run)
    execute_process(COMMAND ${ARGN} RESULT_VARIABLE RET)
    if(NOT RET EQUAL 0)
        list(JOIN ARGN " " CMD)
        message(FATAL_ERROR "command failed [${RET}]: ${CMD}")
    endif()
endfunction()

set(DST ${DESTINATION}/${DLL})
file(MAKE_DIRECTORY ${DESTINATION})
set(STRIP_ARGS --strip-unneeded)
if(KEEP_DEBUG)
    run(${OBJCOPY} --only-keep-debug ${SRC} ${DST}.dbg)
    list(APPEND STRIP_ARGS --add-gnu-debuglink=${DST}.dbg)
endif()
message(STATUS "Installing: ${DST}")
run(${OBJCOPY} ${STRIP_ARGS} ${SRC} ${DST})
