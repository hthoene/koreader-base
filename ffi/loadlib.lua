--[[--
Helper for loading native libraries.

**Example:**

    local sdl = ffi.loadlib("SDL2-2.0", 0, "SDL2-2.0", nil, "SDL2", nil)

Will search `lib_search_path` for the following candidates on Linux:
`libSDL2-2.0.so.0`, `libSDL2-2.0.so`, `libSDL2.so`.

The first one found will be loaded with `ffi.load`, falling back to the
first candidate otherwise (which should be a versioned library to ensure
ABI compatibility).

@module ffi.loadlib

--]]

local ffi = require("ffi")
local android = ffi.os == "Linux" and os.getenv("IS_ANDROID") and require("android")
-- NOTE: the `ffi.log` override is used by some tools to silence loadlib's traces.
local log = ffi.log or android and android.LOGI or print

local monolibtic = {
    path = (android and android.nativeLibraryDir or "libs") .. "/libkoreader-monolibtic." .. (ffi.os == "OSX" and "dylib" or ffi.os == "Windows" and "dll" or "so"),
    redirects = {
        ["archive"]    = true,
        ["blitbuffer"] = true,
        ["crypto"]     = true,
        ["czmq"]       = true,
        ["freetype"]   = true,
        ["fribidi"]    = true,
        ["gif"]        = true,
        ["harfbuzz"]   = true,
        ["jpeg"]       = true,
        ["k2pdfopt"]   = true,
        ["leptonica"]  = true,
        ["lodepng"]    = true,
        ["lunasvg"]    = true,
        ["png16"]      = true,
        ["sharpyuv"]   = true,
        ["sqlite3"]    = true,
        ["ssl"]        = true,
        ["tffi_wrap"]  = true,
        ["turbojpeg"]  = true,
        ["unibreak"]   = true,
        ["utf8proc"]   = true,
        ["webp"]       = true,
        ["webpdemux"]  = true,
        ["wrap-mupdf"] = true,
        ["xxhash"]     = true,
        ["z"]          = true,
        ["zmq"]        = true,
        ["zstd"]       = true,
    },
}
monolibtic.enabled, monolibtic.library = pcall(ffi.load, monolibtic.path)
if monolibtic.enabled then
    log("has monolibtic? yes")
    table.insert(package.loaders, function (modulename)
        local fn
        if modulename:sub(1, 17) == "libs/libkoreader-" then
            -- KOReader Lua modules in `libs/`, loaded with `require("libs/libkoreader-xxx")`.
            fn = "luaopen_" .. modulename:sub(18)
        else
            fn = "luaopen_" .. modulename:gsub("%.", "_")
        end
        log(string.format("package.loadlib: %s [%s]", monolibtic.path, modulename))
        return package.loadlib(monolibtic.path, fn)
    end)
else
    log("has monolibtic? no (" .. monolibtic.library .. ")")
    monolibtic = nil
end

local lib_search_path
local lib_basic_format
local lib_version_format
-- Optional last resort lookup for each candidate (by name).
local lib_fallback

-- Format library name with `lib_version_format` (when versioned) or `lib_basic_format`.
local function libname(name, version)
    return string.format(version and lib_version_format or lib_basic_format, name, version)
end

-- See `ffi.loadlib` for what arguments are expected.
local function findlib(...)
    local name, version = ...
    if not name then
        return
    end
    log("ffi.findlib: " .. name .. (version and (" [" .. version .. "]") or ""))
    if monolibtic and monolibtic.redirects[name] then
        return monolibtic.path
    end
    local lib = libname(name, version)
    local path = package.searchpath(lib, lib_search_path, "/", "/")
    if path then
        return path
    end
    if lib_fallback then
        path = lib_fallback(name)
        if path then
            return path
        end
    end
    return findlib(select(3, ...))
end

local ffi_load = ffi.load

ffi.load = function(lib, global)
    log("ffi.load: " .. lib .. (global and " (RTLD_GLOBAL)" or ""))
    return ffi_load(lib, global)
end

--[[--
Load a native library.

@param ... list of candidates (library name, version)
--]]
ffi.loadlib = function(...)
    local lib = findlib(...) or libname(...)
    return ffi.load(lib)
end

if android then
    -- Note: our libraries are not versioned on Android.
    lib_search_path = android.nativeLibraryDir .. "/?"
    -- Unversioned: libz.so
    lib_basic_format = "lib%s.so"
    -- Versioned: libz.so
    lib_version_format = "lib%s.so"
    if not monolibtic then
        -- Android need some custom code for KOReader Lua modules loaded
        -- with `require("libs/libkoreader-xxx")`, but actually stored
        -- under the application's directory for native libraries.
        table.insert(package.loaders, 1, function (modulename)
            if modulename:sub(1, 17) ~= "libs/libkoreader-" then
                return
            end
            local path = android.nativeLibraryDir .. "/" .. libname(modulename:sub(9))
            log(string.format("package.loadlib: %s [%s]", path, modulename))
            return package.loadlib(path, "luaopen_" .. modulename:sub(18))
        end)
    end
elseif ffi.os == "Linux" then
    lib_search_path = "libs/?"
    -- Unversioned: libz.so
    lib_basic_format = "lib%s.so"
    -- Versioned: libz.so.1
    lib_version_format = "lib%s.so.%s"
elseif ffi.os == "OSX" then
    -- Apple M1 homebrew installs libraries outside of default search paths,
    -- and dyld environment variables are sip-protected on MacOS, cf.
    -- https://github.com/Homebrew/brew/issues/13481#issuecomment-1181592842
    local libprefix = os.getenv("KO_DYLD_PREFIX")
    if not libprefix then
        local std_out = io.popen("brew --prefix", "r")
        if std_out then
            libprefix = std_out:read("*line")
            std_out:close()
        end
    end
    lib_search_path = "libs/?"
    if libprefix then
        lib_search_path = lib_search_path .. ";" .. libprefix .. "/lib/?"
    end
    -- Unversioned: libz.dylib
    lib_basic_format = "lib%s.dylib"
    -- Versioned: libz.1.dylib
    lib_version_format = "lib%s.%s.dylib"
elseif ffi.os == "Windows" then
    -- NOTE: use the native path separator (c.f. `LoadLibraryEx`).
    lib_search_path = "libs\\?"
    -- Unversioned: libz.dll
    lib_basic_format = "lib%s.dll"
    -- Versioned: libfreetype-6.dll
    lib_version_format = "lib%s-%s.dll"
    -- DLL names do not follow a single convention (e.g. `libz.dll`, `libfreetype-6.dll`,
    -- `libleptonica-1.87.0.dll`, `SDL3.dll`): so try them all, in that order.
    local libs
    lib_fallback = function(name)
        for __, lib in ipairs{ "lib" .. name .. ".dll", name .. ".dll" } do
            local path = package.searchpath(lib, lib_search_path, "/", "/")
            if path then
                return path
            end
        end
        -- Any version: `lib<name>-<version>.dll`.
        if not libs then
            libs = {}
            local lfs = require("libs/libkoreader-lfs")
            local ok, iter, dir_obj = pcall(lfs.dir, "libs")
            if ok then
                for f in iter, dir_obj do
                    table.insert(libs, f)
                end
            end
        end
        local pattern = "^lib" .. name:gsub("%p", "%%%0") .. "%-[%d.]+%.dll$"
        for __, f in ipairs(libs) do
            if f:match(pattern) then
                return "libs" .. package.config:sub(1, 1) .. f
            end
        end
    end
end

log("lib_search_path: " .. lib_search_path)
log("lib_basic_format: " .. lib_basic_format)
log("lib_version_format: " .. lib_version_format)
