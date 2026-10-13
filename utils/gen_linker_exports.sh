#!/usr/bin/env bash

set -eo pipefail

debug=0

# `--pe`: target PE/COFF (Windows): use a module-definition file.
pe=0
if [[ "$1" == '--pe' ]]; then
    pe=1
    shift
fi

[[ $# -gt 3 ]]

linker="$1"
link_args="$2"
exports_script="$3"
shift 3

if [[ ${pe} -eq 1 ]]; then
    # NOTE: the module-definition file is passed as a linker input; only the
    # symbols it lists are exported (and they must be defined), so there's no
    # need to add undefined references.
    linker_version='PE/COFF'
else
    linker_version="$("${linker}" -v 2>&1)"
fi
case "${linker_version}" in
    PE/COFF)
        symarg=''
        vsarg='%s\n'
        vsfmt='def'
        ;;
    *PROJECT:ld64-* | *PROJECT:dyld-* | *PROJECT:ld-*)
        symarg='-u _%s\n'
        vsarg='-exported_symbols_list %s\n'
        vsfmt='export'
        ;;
    GNU\ ld\ * | mold\ *)
        symarg='--require-defined=%s\n'
        vsarg='--version-script=%s\n'
        vsfmt='version'
        ;;
    GNU\ gold | LLD\ *)
        symarg='--undefined=%s\n'
        vsarg='--version-script=%s\n'
        vsfmt='version'
        ;;
    *)
        # symarg=''
        # vsarg=''
        # vsfmt='blank'
        echo "unsupported linker: ${linker} [${linker_version}]" 1>&2
        exit 1
        ;;
esac

if [[ ${debug} -eq 1 ]]; then
    echo "symarg: ${symarg}"
    echo "vsarg: ${vsarg}"
    echo "vsfmt: ${vsfmt}"
fi

out="$(sed -E -n -e 's,^[[:space:]]*cdecl_(func|var)\(([^)]+)\)[[:space:]]*;?[[:space:]]*(/[/*].*)?$,\2,p' "$@" | sort -u)"
read -r -d '' -a symbols <<<"${out}" || true

if [[ ${debug} -eq 1 ]]; then
    echo "symbols: [${#symbols[@]}]"
    printf '%s\n' "${symbols[@]}"
fi

{
    if [[ -n "${symarg}" ]]; then
        # shellcheck disable=SC2059
        printf -- "${symarg}" "${symbols[@]}"
    fi
    # shellcheck disable=SC2059
    printf -- "${vsarg}" "${exports_script}"
} >"${link_args}"

if [[ ${debug} -eq 1 ]]; then
    echo "${link_args}:"
    cat "${link_args}"
fi

case "${vsfmt}" in
    blank)
        touch "${exports_script}"
        ;;
    export)
        {
            printf '_%s\n' "${symbols[@]}"
        } >"${exports_script}"
        ;;
    def)
        {
            printf 'EXPORTS\n'
            printf '  %s\n' "${symbols[@]}"
        } >"${exports_script}"
        ;;
    version)
        {
            printf '{\nglobal:\n'
            printf '  %s;\n' "${symbols[@]}"
            printf 'local: *;\n};\n'
        } >"${exports_script}"
        ;;
    *)
        echo "unsupported export script format: ${vsfmt}" 1>&2
        exit 1
        ;;
esac

if [[ ${debug} -eq 1 ]]; then
    echo "${exports_script}:"
    cat "${exports_script}"
fi

# vim: sw=4
