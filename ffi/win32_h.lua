--[[--
Declarations for the (small) subset of the Win32 API we use.

NOTE: the process code page is UTF-8 (c.f. the application manifest),
so the "A" variants of the APIs can be used with UTF-8 strings.
--]]

local ffi = require("ffi")

ffi.cdef[[
typedef int BOOL;
typedef unsigned char BYTE;
typedef unsigned short WORD;
typedef unsigned long DWORD;
typedef unsigned int UINT;
typedef long LONG;
typedef int64_t LONGLONG;
typedef uint64_t ULONGLONG;
typedef void *HANDLE;
typedef void *HWND;
typedef void *HINSTANCE;
typedef void *LPVOID;
typedef const void *LPCVOID;
typedef char *LPSTR;
typedef const char *LPCSTR;
typedef wchar_t *LPWSTR;
typedef const wchar_t *LPCWSTR;
typedef BOOL *LPBOOL;
typedef DWORD *LPDWORD;
typedef uintptr_t ULONG_PTR;
typedef ULONG_PTR SIZE_T;

typedef union _LARGE_INTEGER {
  struct {
    DWORD LowPart;
    LONG HighPart;
  };
  LONGLONG QuadPart;
} LARGE_INTEGER;

typedef union _ULARGE_INTEGER {
  struct {
    DWORD LowPart;
    DWORD HighPart;
  };
  ULONGLONG QuadPart;
} ULARGE_INTEGER;

typedef long HRESULT;

typedef struct _GUID {
  uint32_t Data1;
  uint16_t Data2;
  uint16_t Data3;
  uint8_t Data4[8];
} GUID;

typedef struct _FILETIME {
  DWORD dwLowDateTime;
  DWORD dwHighDateTime;
} FILETIME;

typedef struct _SECURITY_ATTRIBUTES {
  DWORD nLength;
  LPVOID lpSecurityDescriptor;
  BOOL bInheritHandle;
} SECURITY_ATTRIBUTES;

typedef struct _STARTUPINFOW {
  DWORD cb;
  LPWSTR lpReserved;
  LPWSTR lpDesktop;
  LPWSTR lpTitle;
  DWORD dwX;
  DWORD dwY;
  DWORD dwXSize;
  DWORD dwYSize;
  DWORD dwXCountChars;
  DWORD dwYCountChars;
  DWORD dwFillAttribute;
  DWORD dwFlags;
  WORD wShowWindow;
  WORD cbReserved2;
  BYTE *lpReserved2;
  HANDLE hStdInput;
  HANDLE hStdOutput;
  HANDLE hStdError;
} STARTUPINFOW;

typedef struct _PROC_THREAD_ATTRIBUTE_LIST *LPPROC_THREAD_ATTRIBUTE_LIST;

typedef struct _STARTUPINFOEXW {
  STARTUPINFOW StartupInfo;
  LPPROC_THREAD_ATTRIBUTE_LIST lpAttributeList;
} STARTUPINFOEXW;

typedef struct _PROCESS_INFORMATION {
  HANDLE hProcess;
  HANDLE hThread;
  DWORD dwProcessId;
  DWORD dwThreadId;
} PROCESS_INFORMATION;

static const DWORD ERROR_FILE_NOT_FOUND = 2;
static const DWORD ERROR_ACCESS_DENIED = 5;
static const DWORD ERROR_BROKEN_PIPE = 109;
static const DWORD ERROR_ALREADY_EXISTS = 183;
static const DWORD INFINITE = 0xFFFFFFFF;
static const DWORD WAIT_OBJECT_0 = 0;
static const DWORD WAIT_TIMEOUT = 258;
static const DWORD STILL_ACTIVE = 259;
static const DWORD INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF;
static const DWORD FILE_ATTRIBUTE_HIDDEN = 0x2;
static const DWORD FILE_ATTRIBUTE_SYSTEM = 0x4;
static const DWORD FILE_ATTRIBUTE_DIRECTORY = 0x10;
static const DWORD HANDLE_FLAG_INHERIT = 0x1;
static const DWORD STD_ERROR_HANDLE = -12;
static const DWORD STARTF_USESTDHANDLES = 0x100;
static const DWORD CREATE_NO_WINDOW = 0x08000000;
static const DWORD CREATE_UNICODE_ENVIRONMENT = 0x400;
static const DWORD EXTENDED_STARTUPINFO_PRESENT = 0x80000;
static const DWORD BELOW_NORMAL_PRIORITY_CLASS = 0x4000;
static const DWORD PROC_THREAD_ATTRIBUTE_HANDLE_LIST = 0x20002;
static const DWORD MOVEFILE_REPLACE_EXISTING = 0x1;
static const DWORD MOVEFILE_COPY_ALLOWED = 0x2;
static const DWORD MOVEFILE_WRITE_THROUGH = 0x8;
static const DWORD FORMAT_MESSAGE_IGNORE_INSERTS = 0x200;
static const DWORD FORMAT_MESSAGE_FROM_SYSTEM = 0x1000;
static const UINT CP_UTF8 = 65001;
static const UINT DRIVE_UNKNOWN = 0;
static const UINT DRIVE_NO_ROOT_DIR = 1;
static const UINT DRIVE_REMOVABLE = 2;
static const UINT DRIVE_FIXED = 3;
static const UINT DRIVE_REMOTE = 4;
static const UINT DRIVE_CDROM = 5;
static const UINT DRIVE_RAMDISK = 6;

DWORD GetLastError(void);
DWORD FormatMessageA(DWORD, LPCVOID, DWORD, DWORD, LPSTR, DWORD, void *);
int MultiByteToWideChar(UINT, DWORD, LPCSTR, int, LPWSTR, int);
int WideCharToMultiByte(UINT, DWORD, LPCWSTR, int, LPSTR, int, LPCSTR, LPBOOL);
UINT GetACP(void);

void Sleep(DWORD);
BOOL QueryPerformanceCounter(LARGE_INTEGER *);
BOOL QueryPerformanceFrequency(LARGE_INTEGER *);
void GetSystemTimePreciseAsFileTime(FILETIME *);
ULONGLONG GetTickCount64(void);
BOOL QueryUnbiasedInterruptTime(ULONGLONG *);

DWORD GetFullPathNameA(LPCSTR, DWORD, LPSTR, LPSTR *);
DWORD GetFileAttributesA(LPCSTR);
BOOL MoveFileExA(LPCSTR, LPCSTR, DWORD);
BOOL GetDiskFreeSpaceExA(LPCSTR, ULARGE_INTEGER *, ULARGE_INTEGER *, ULARGE_INTEGER *);
DWORD GetLogicalDrives(void);
UINT GetDriveTypeA(LPCSTR);
BOOL GetVolumeInformationA(LPCSTR, LPSTR, DWORD, LPDWORD, LPDWORD, LPDWORD, LPSTR, DWORD);
DWORD GetEnvironmentVariableA(LPCSTR, LPSTR, DWORD);

HANDLE GetStdHandle(DWORD);
BOOL CloseHandle(HANDLE);
BOOL GetHandleInformation(HANDLE, LPDWORD);
BOOL SetHandleInformation(HANDLE, DWORD, DWORD);
BOOL CreatePipe(HANDLE *, HANDLE *, SECURITY_ATTRIBUTES *, DWORD);
BOOL PeekNamedPipe(HANDLE, LPVOID, DWORD, LPDWORD, LPDWORD, LPDWORD);
BOOL ReadFile(HANDLE, LPVOID, DWORD, LPDWORD, void *);
BOOL InitializeProcThreadAttributeList(LPPROC_THREAD_ATTRIBUTE_LIST, DWORD, DWORD, SIZE_T *);
BOOL UpdateProcThreadAttribute(LPPROC_THREAD_ATTRIBUTE_LIST, DWORD, ULONG_PTR, void *, SIZE_T, void *, SIZE_T *);
void DeleteProcThreadAttributeList(LPPROC_THREAD_ATTRIBUTE_LIST);
BOOL CreateProcessW(LPCWSTR, LPWSTR, SECURITY_ATTRIBUTES *, SECURITY_ATTRIBUTES *, BOOL, DWORD, LPVOID, LPCWSTR, STARTUPINFOW *, PROCESS_INFORMATION *);
DWORD WaitForSingleObject(HANDLE, DWORD);
BOOL GetExitCodeProcess(HANDLE, LPDWORD);
BOOL TerminateProcess(HANDLE, UINT);
/* NOTE: the start routine (`LPTHREAD_START_ROUTINE`) is declared as an opaque pointer, so we
 *       can pass a `void *(*)(void *)` function (they're ABI compatible on 64-bit Windows). */
HANDLE CreateThread(SECURITY_ATTRIBUTES *, SIZE_T, void *, LPVOID, DWORD, LPDWORD);

/* shell32 */
HRESULT SHGetKnownFolderPath(const GUID *, DWORD, HANDLE, LPWSTR *);
/* ole32 */
void CoTaskMemFree(LPVOID);
]]
