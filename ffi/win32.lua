--[[--
Windows helpers.

@module ffi.win32
]]

local bit = require("bit")
local ffi = require("ffi")
local C = ffi.C

require("ffi/win32_h")

local win32 = {}

--- Convert an UTF-8 string to a NUL terminated UTF-16 buffer (for the "W" APIs).
function win32.toWide(str)
    local len = C.MultiByteToWideChar(C.CP_UTF8, 0, str, #str, nil, 0)
    local buf = ffi.new("wchar_t[?]", len + 1)
    if len > 0 then
        C.MultiByteToWideChar(C.CP_UTF8, 0, str, #str, buf, len)
    end
    buf[len] = 0
    return buf
end

--- Convert a NUL terminated UTF-16 string (from the "W" APIs) to UTF-8.
function win32.fromWide(wstr)
    local len = C.WideCharToMultiByte(C.CP_UTF8, 0, wstr, -1, nil, 0, nil, nil)
    if len <= 1 then
        return ""
    end
    local buf = ffi.new("char[?]", len)
    C.WideCharToMultiByte(C.CP_UTF8, 0, wstr, -1, buf, len, nil, nil)
    return ffi.string(buf, len - 1)
end

--- Human readable message for a Win32 error code (defaults to `GetLastError()`).
function win32.errorString(code)
    code = code or C.GetLastError()
    local buf = ffi.new("char[512]")
    local len = C.FormatMessageA(bit.bor(C.FORMAT_MESSAGE_FROM_SYSTEM, C.FORMAT_MESSAGE_IGNORE_INSERTS),
                                 nil, code, 0, buf, ffi.sizeof(buf), nil)
    if len == 0 then
        return string.format("error %u", code)
    end
    return (ffi.string(buf, len):gsub("%s+$", ""))
end

--- Quote a command line argument (as expected by `CommandLineToArgvW` & the C runtime).
function win32.quoteArg(arg)
    if arg ~= "" and not arg:find('[%s"]') then
        return arg
    end
    -- Backslashes are only special when followed by a quote:
    -- double them, and escape the quote.
    arg = arg:gsub('(\\*)"', function(backslashes)
        return backslashes .. backslashes .. '\\"'
    end)
    -- Same for trailing backslashes (followed by the closing quote).
    arg = arg:gsub("(\\+)$", "%1%1")
    return '"' .. arg .. '"'
end

-- Process. {{{

local Process = {}
Process.__index = Process

--- Number of bytes that can be read from the standard output without blocking.
-- Returns 1 at the end of the output (so callers don't wait for output that will never come).
function Process:available()
    if not self.stdout then
        return 1
    end
    local avail = ffi.new("DWORD[1]")
    if C.PeekNamedPipe(self.stdout, nil, 0, nil, avail, nil) == 0 then
        -- Most likely `ERROR_BROKEN_PIPE`: the program exited.
        return 1
    end
    return tonumber(avail[0])
end

local function read_all(self)
    local chunks = {}
    if self.buffer then
        table.insert(chunks, self.buffer)
        self.buffer = nil
    end
    if self.stdout then
        local size = 65536
        local buf = ffi.new("char[?]", size)
        local nread = ffi.new("DWORD[1]")
        while C.ReadFile(self.stdout, buf, size, nread, nil) ~= 0 and nread[0] > 0 do
            table.insert(chunks, ffi.string(buf, nread[0]))
        end
        C.CloseHandle(self.stdout)
        self.stdout = nil
    end
    return table.concat(chunks)
end

--- Read the standard output (like `file:read`): only `"*a"` and `"*l"` formats are supported.
function Process:read(fmt)
    fmt = (fmt or "*l"):gsub("^%*", "")
    if fmt == "a" then
        return read_all(self)
    end
    assert(fmt == "l", "unsupported format: " .. fmt)
    self.buffer = read_all(self)
    if self.buffer == "" then
        return nil
    end
    local line, rest = self.buffer:match("^([^\n]*)\n?(.*)$")
    self.buffer = rest
    return (line:gsub("\r$", ""))
end

--- Iterate over the lines of the standard output (like `file:lines`).
function Process:lines()
    return function() return self:read("*l") end
end

--- Wait for the program to exit (with an optional timeout in milliseconds).
-- Returns the exit code, or nil if the program is still running.
function Process:wait(timeout_ms)
    if self.exit_code then
        return self.exit_code
    end
    if C.WaitForSingleObject(self.handle, timeout_ms or C.INFINITE) ~= C.WAIT_OBJECT_0 then
        return
    end
    local code = ffi.new("DWORD[1]")
    C.GetExitCodeProcess(self.handle, code)
    C.CloseHandle(self.handle)
    self.handle = nil
    self.exit_code = tonumber(code[0])
    return self.exit_code
end

--- Let the program run on its own (we won't wait for it, nor read its output).
function Process:detach()
    if self.stdout then
        C.CloseHandle(self.stdout)
        self.stdout = nil
    end
    if self.handle then
        C.CloseHandle(self.handle)
        self.handle = nil
    end
end

--- Forcefully terminate the program.
function Process:kill()
    if self.handle then
        C.TerminateProcess(self.handle, 1)
    end
end

--- Close the standard output, and wait for the program to exit (like `file:close`).
function Process:close()
    if self.stdout then
        C.CloseHandle(self.stdout)
        self.stdout = nil
    end
    local code = self:wait()
    if code == 0 then
        return true
    end
    return nil, "exit", code
end

-- Create a pipe, only one end of which (`"read"` or `"write"`) is inheritable by a child process.
local function create_pipe(child_end, size)
    local sa = ffi.new("SECURITY_ATTRIBUTES", ffi.sizeof("SECURITY_ATTRIBUTES"), nil, 1)
    local pipe = ffi.new("HANDLE[2]")
    if C.CreatePipe(pipe, pipe + 1, sa, size or 0) == 0 then
        return nil, nil, "CreatePipe: " .. win32.errorString()
    end
    C.SetHandleInformation(pipe[child_end == "read" and 1 or 0], C.HANDLE_FLAG_INHERIT, 0)
    return pipe[0], pipe[1]
end

-- Write all of `data` to a handle.
local function write_all(handle, data)
    local written = ffi.new("DWORD[1]")
    local offset = 0
    while offset < #data do
        if C.WriteFile(handle, ffi.cast("const char *", data) + offset, #data - offset, written, nil) == 0 then
            return false
        end
        offset = offset + written[0]
    end
    return true
end

--[[--
Run a program, without going through a shell (and without a console window).

The standard error is redirected to our own (i.e. the log), when available.

@tparam {string,...} args the program and its arguments
@tparam[opt] table options:

- `capture_stdout`: capture the standard output (c.f. @{Process:read})
- `input`: data written to the standard input (which is then closed)
- `background`: run with a lower priority (for non-interactive tasks)

@treturn Process|nil the started program, or nil on failure
@treturn string error message (on failure)
]]
function win32.spawn(args, options)
    options = options or {}
    local inherit = {}
    local err
    local stdout_read, stdout_write
    if options.capture_stdout then
        stdout_read, stdout_write, err = create_pipe("write")
        if not stdout_read then
            return nil, err
        end
        table.insert(inherit, stdout_write)
    end
    local stdin_read, stdin_write
    if options.input then
        -- NOTE: with a big enough buffer, writing the input won't block.
        stdin_read, stdin_write, err = create_pipe("read", #options.input + 4096)
        if not stdin_read then
            if stdout_read then
                C.CloseHandle(stdout_read)
                C.CloseHandle(stdout_write)
            end
            return nil, err
        end
        table.insert(inherit, stdin_read)
    end
    -- Close the child ends of the pipes (and ours too on failure).
    local function close_pipes(ours_too)
        local handles = { stdout_write, stdin_read, ours_too and stdout_read, ours_too and stdin_write }
        for i = 1, 4 do
            if handles[i] then
                C.CloseHandle(handles[i])
            end
        end
    end
    local stderr = C.GetStdHandle(C.STD_ERROR_HANDLE)
    local flags = ffi.new("DWORD[1]")
    if stderr ~= nil and ffi.cast("intptr_t", stderr) ~= -1
       and C.GetHandleInformation(stderr, flags) ~= 0 and bit.band(flags[0], C.HANDLE_FLAG_INHERIT) ~= 0 then
        table.insert(inherit, stderr)
    else
        stderr = nil
    end

    local si = ffi.new("STARTUPINFOEXW")
    si.StartupInfo.cb = ffi.sizeof(si)
    si.StartupInfo.dwFlags = C.STARTF_USESTDHANDLES
    si.StartupInfo.hStdInput = stdin_read
    si.StartupInfo.hStdOutput = stdout_write
    si.StartupInfo.hStdError = stderr
    local creation_flags = C.CREATE_NO_WINDOW
    if options.background then
        creation_flags = bit.bor(creation_flags, C.BELOW_NORMAL_PRIORITY_CLASS)
    end
    -- Only inherit the handles we need (in particular, not the files we have opened,
    -- as Windows would then prevent renaming or deleting them).
    local attrs_buf, handles
    if #inherit > 0 then
        local size = ffi.new("SIZE_T[1]")
        C.InitializeProcThreadAttributeList(nil, 1, 0, size)
        attrs_buf = ffi.new("uint8_t[?]", size[0])
        si.lpAttributeList = ffi.cast("LPPROC_THREAD_ATTRIBUTE_LIST", attrs_buf)
        handles = ffi.new("HANDLE[?]", #inherit, inherit)
        if C.InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, size) == 0
           or C.UpdateProcThreadAttribute(si.lpAttributeList, 0, C.PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                          handles, ffi.sizeof(handles), nil, nil) == 0 then
            err = win32.errorString()
            close_pipes(true)
            return nil, "UpdateProcThreadAttribute: " .. err
        end
        creation_flags = bit.bor(creation_flags, C.EXTENDED_STARTUPINFO_PRESENT)
    end

    local quoted = {}
    for i, arg in ipairs(args) do
        quoted[i] = win32.quoteArg(arg)
    end
    local cmdline = win32.toWide(table.concat(quoted, " "))
    local pi = ffi.new("PROCESS_INFORMATION")
    local ok = C.CreateProcessW(nil, cmdline, nil, nil, #inherit > 0 and 1 or 0, creation_flags,
                                nil, nil, ffi.cast("STARTUPINFOW *", si), pi)
    err = ok == 0 and win32.errorString()
    if si.lpAttributeList ~= nil then
        C.DeleteProcThreadAttributeList(si.lpAttributeList)
    end
    close_pipes(ok == 0)
    if ok == 0 then
        return nil, string.format("CreateProcess(%s): %s", args[1], err)
    end
    C.CloseHandle(pi.hThread)
    if stdin_write then
        -- NOTE: may fail if the program already exited (without reading it).
        write_all(stdin_write, options.input)
        C.CloseHandle(stdin_write)
    end
    return setmetatable({
        handle = pi.hProcess,
        pid = tonumber(pi.dwProcessId),
        stdout = stdout_read,
    }, Process)
end

--[[--
Take over the standard output, e.g. to use it as a (binary) channel to the parent process:
anything else written to it from now on (e.g. logs) goes to the standard error instead.

@treturn function write function (`write(data)`, returns true on success), or nil if
there's no standard output
]]
function win32.takeStdout()
    require("ffi/posix_h")
    local process = C.GetCurrentProcess()
    local stdout = C.GetStdHandle(C.STD_OUTPUT_HANDLE)
    local handle = ffi.new("HANDLE[1]")
    -- Keep our own copy (the C runtime closes its own when redirected below).
    if stdout == nil or ffi.cast("intptr_t", stdout) == -1
       or C.DuplicateHandle(process, stdout, process, handle, 0, 0, C.DUPLICATE_SAME_ACCESS) == 0 then
        handle = nil
    end
    -- Redirect both the C runtime and the Windows standard outputs.
    if C.dup2(2, 1) ~= 0 then
        local null = C.open("NUL", C.O_WRONLY)
        if null >= 0 then
            C.dup2(null, 1)
            C.close(null)
        end
    end
    C.SetStdHandle(C.STD_OUTPUT_HANDLE, C.GetStdHandle(C.STD_ERROR_HANDLE))
    if not handle then
        return
    end
    handle = handle[0]
    return function(data)
        return write_all(handle, data)
    end
end

--- Read all of the standard input (as is: unlike `io.stdin`, without any newline translation).
function win32.readStdin()
    return read_all({ stdout = C.GetStdHandle(C.STD_INPUT_HANDLE) })
end

-- }}}

-- Memory. {{{

--[[--
Get the physical memory status.

@treturn int available memory (in bytes), or nil on error
@treturn int total memory (in bytes), or the error message
]]
function win32.getMemoryStatus()
    local status = ffi.new("MEMORYSTATUSEX")
    status.dwLength = ffi.sizeof(status)
    if C.GlobalMemoryStatusEx(status) == 0 then
        return nil, win32.errorString()
    end
    return tonumber(status.ullAvailPhys), tonumber(status.ullTotalPhys)
end

-- }}}

-- Files. {{{

local HIDDEN_ATTRIBUTES = bit.bor(C.FILE_ATTRIBUTE_HIDDEN, C.FILE_ATTRIBUTE_SYSTEM)

--- Whether a file (or directory) is hidden (or a system file, which Windows also hides by default).
function win32.isHidden(path)
    local attributes = C.GetFileAttributesA(path)
    return attributes ~= C.INVALID_FILE_ATTRIBUTES and bit.band(attributes, HIDDEN_ATTRIBUTES) ~= 0
end

-- }}}

-- Drives. {{{

local DRIVE_TYPES = {
    [C.DRIVE_REMOVABLE] = "removable",
    [C.DRIVE_FIXED] = "fixed",
    [C.DRIVE_REMOTE] = "remote",
    [C.DRIVE_CDROM] = "cdrom",
    [C.DRIVE_RAMDISK] = "ramdisk",
}

--[[--
List the available drives.

@treturn {{path=string,letter=string,type=string,label=string|nil},...}
    e.g. `{ path = "C:/", letter = "C", type = "fixed", label = "Windows" }`
]]
function win32.getDrives()
    local drives = {}
    local mask = C.GetLogicalDrives()
    local label = ffi.new("char[261]")
    for i = 0, 25 do
        if bit.band(mask, bit.lshift(1, i)) ~= 0 then
            local letter = string.char(65 + i)
            local path = letter .. ":/"
            local drive_type = DRIVE_TYPES[C.GetDriveTypeA(path)]
            if drive_type then
                local drive = { path = path, letter = letter, type = drive_type }
                -- NOTE: querying a disconnected network drive can block for a long time.
                if drive_type ~= "remote"
                   and C.GetVolumeInformationA(path, label, ffi.sizeof(label), nil, nil, nil, nil, 0) ~= 0
                   and label[0] ~= 0 then
                    drive.label = ffi.string(label)
                end
                table.insert(drives, drive)
            end
        end
    end
    return drives
end

-- }}}

-- Known folders. {{{

local shell32, ole32

local KNOWN_FOLDERS = {
    -- FOLDERID_Documents
    Documents = { 0xFDD39AD0, 0x238F, 0x46AF, { 0xAD, 0xB4, 0x6C, 0x85, 0x48, 0x03, 0x69, 0xC7 } },
    -- FOLDERID_Downloads
    Downloads = { 0x374DE290, 0x123F, 0x4565, { 0x91, 0x64, 0x39, 0xC4, 0x92, 0x5E, 0x46, 0x7B } },
    -- FOLDERID_LocalAppData
    LocalAppData = { 0xF1B32785, 0x6FBA, 0x4FCF, { 0x9D, 0x55, 0x7B, 0x8E, 0x7F, 0x15, 0x70, 0x91 } },
}

--[[--
Path to a known folder (e.g. `Documents`, which may be redirected to OneDrive).

@string name one of `Documents`, `Downloads`, or `LocalAppData`
@treturn string|nil the path (with forward slashes as separators)
]]
function win32.getKnownFolder(name)
    shell32 = shell32 or ffi.load("shell32")
    ole32 = ole32 or ffi.load("ole32")
    local guid = ffi.new("GUID", KNOWN_FOLDERS[name])
    local path = ffi.new("LPWSTR[1]")
    local ok = shell32.SHGetKnownFolderPath(guid, 0, nil, path) == 0
    local res = ok and win32.fromWide(path[0]):gsub("\\", "/") or nil
    -- NOTE: must be freed even on failure.
    ole32.CoTaskMemFree(path[0])
    return res
end

-- }}}

-- Libraries. {{{

--[[--
Look for the dependencies of the libraries we load in `dir` first (before the
system directories, which may contain incompatible libraries with the same name).

NOTE: the launcher already does that, but not the standalone LuaJIT interpreter.
]]
function win32.setDllDirectory(dir)
    local size = C.GetFullPathNameA(dir, 0, nil, nil)
    local buffer = ffi.new("char[?]", size)
    if size == 0 or C.GetFullPathNameA(dir, size, buffer, nil) == 0 or C.SetDllDirectoryA(buffer) == 0 then
        return false, win32.errorString()
    end
    return true
end

-- }}}

-- Standard library. {{{

--[[--
Make some standard library functions behave like on POSIX systems:

- `os.rename` replaces an existing destination (atomically for files on the same volume).
- `os.remove` can also remove (empty) directories.
- `lfs.currentdir` uses forward slashes as path separators (like the rest of our code).
]]
function win32.setupStdlib()
    require("ffi/posix_h")
    -- Open files in binary mode by default (no newline translation), like on other platforms
    -- (our launcher already does it, but not the standalone LuaJIT interpreter).
    C._set_fmode(0x8000) -- _O_BINARY
    local lfs = require("libs/libkoreader-lfs")
    local lfs_currentdir = lfs.currentdir
    lfs.currentdir = function()
        local dir, err = lfs_currentdir()
        if dir then
            dir = dir:gsub("\\", "/")
        end
        return dir, err
    end
    -- Map the Windows errors to `errno` values (like the C runtime does).
    local ERRNO_FROM_ERROR = {
        [2] = 2,      -- ERROR_FILE_NOT_FOUND: ENOENT
        [3] = 2,      -- ERROR_PATH_NOT_FOUND: ENOENT
        [5] = 13,     -- ERROR_ACCESS_DENIED: EACCES
        [17] = 18,    -- ERROR_NOT_SAME_DEVICE: EXDEV
        [19] = 13,    -- ERROR_WRITE_PROTECT: EACCES
        [32] = 13,    -- ERROR_SHARING_VIOLATION: EACCES
        [33] = 13,    -- ERROR_LOCK_VIOLATION: EACCES
        [39] = 28,    -- ERROR_HANDLE_DISK_FULL: ENOSPC
        [80] = 17,    -- ERROR_FILE_EXISTS: EEXIST
        [112] = 28,   -- ERROR_DISK_FULL: ENOSPC
        [145] = 41,   -- ERROR_DIR_NOT_EMPTY: ENOTEMPTY
        [183] = 17,   -- ERROR_ALREADY_EXISTS: EEXIST
    }
    local rename_flags = bit.bor(C.MOVEFILE_REPLACE_EXISTING, C.MOVEFILE_COPY_ALLOWED, C.MOVEFILE_WRITE_THROUGH)
    os.rename = function(oldname, newname) -- luacheck: ignore 122
        if C.MoveFileExA(oldname, newname, rename_flags) ~= 0 then
            return true
        end
        local errno = ERRNO_FROM_ERROR[C.GetLastError()] or C.EINVAL
        return nil, string.format("%s: %s", oldname, ffi.string(C.strerror(errno))), errno
    end
    local os_remove = os.remove
    os.remove = function(path) -- luacheck: ignore 122
        local ok, err, code = os_remove(path)
        if not ok and lfs.attributes(path, "mode") == "directory" then
            return lfs.rmdir(path)
        end
        return ok, err, code
    end
end

-- }}}

return win32

-- vim: foldmethod=marker foldlevel=0
