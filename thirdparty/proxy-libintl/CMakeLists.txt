project(proxy-libintl LANGUAGES)

list(APPEND CFG_CMD COMMAND
    ${MESON_SETUP} --default-library=static
    "${SOURCE_DIR}"
)

list(APPEND BUILD_CMD COMMAND ninja)

list(APPEND BUILD_CMD COMMAND ${MESON_INSTALL})

if(WIN32)
    # We only build a static library: ensure the header
    # does not declare the API with `__declspec(dllimport)`.
    list(APPEND BUILD_CMD COMMAND ${ISED} "1i #define G_INTL_STATIC_COMPILATION 1" ${STAGING_DIR}/include/libintl.h)
endif()

external_project(
    DOWNLOAD URL 7cc93d2fec98a5b9820888135d2e8844
    https://github.com/frida/proxy-libintl/archive/refs/tags/0.4.tar.gz
    CONFIGURE_COMMAND ${CFG_CMD}
    BUILD_COMMAND ${BUILD_CMD}
)
