--[[--
POSIX declarations for Windows (c.f. `ffi/posix_h`).

The (Universal) C runtime only provides a subset of the POSIX API, often under
different names (e.g. `_open`), which are mapped here using symbol redirection.
Only what makes sense on Windows is declared: the rest (e.g. `fork`, `mmap`)
is left undefined, so unsupported code paths fail early and loudly.

NOTE: files are always opened in binary mode (c.f. `O_RDONLY` & co below).
--]]

local ffi = require("ffi")

ffi.cdef[[
static const unsigned EPERM = 1;
static const unsigned ENOENT = 2;
static const unsigned EINTR = 4;
static const unsigned EAGAIN = 11;
static const unsigned ENODEV = 19;
static const unsigned EINVAL = 22;
static const unsigned EPIPE = 32;
static const unsigned ENOSYS = 40;
static const unsigned ETIME = 137;
static const unsigned ETIMEDOUT = 138;

/* NOTE: `_O_BINARY` (0x8000) is included in the access modes, so *all* our
 *       descriptors are in binary mode (no newlines or EOF translation). */
static const unsigned O_RDONLY = 0x8000;
static const unsigned O_WRONLY = 0x8001;
static const unsigned O_RDWR = 0x8002;
static const unsigned O_APPEND = 0x0008;
static const unsigned O_CREAT = 0x0100;
static const unsigned O_TRUNC = 0x0200;
static const unsigned O_EXCL = 0x0400;
/* `_O_NOINHERIT` */
static const unsigned O_CLOEXEC = 0x0080;
/* Not supported. */
static const unsigned O_NONBLOCK = 0;

static const unsigned F_OK = 0;
static const unsigned W_OK = 2;
static const unsigned R_OK = 4;
/* `_access` does not support checking for execute permissions. */
static const unsigned X_OK = 0;

/* Only `_S_IREAD` & `_S_IWRITE` are supported (no group / others permissions). */
static const unsigned S_IRUSR = 0x0100;
static const unsigned S_IWUSR = 0x0080;
static const unsigned S_IXUSR = 0;
static const unsigned S_IRWXU = 0x0180;
static const unsigned S_IRGRP = 0;
static const unsigned S_IWGRP = 0;
static const unsigned S_IXGRP = 0;
static const unsigned S_IRWXG = 0;
static const unsigned S_IROTH = 0;
static const unsigned S_IWOTH = 0;
static const unsigned S_IXOTH = 0;
static const unsigned S_IRWXO = 0;

static const unsigned SEEK_SET = 0;
static const unsigned SEEK_CUR = 1;
static const unsigned SEEK_END = 2;

/* NOTE: not a hard limit on Windows (long paths support), but a sensible buffer
 *       size for UTF-8 encoded paths. */
static const unsigned PATH_MAX = 4096;

/* Clock identifiers (c.f. `ui/time`). */
static const unsigned CLOCK_REALTIME = 0;
static const unsigned CLOCK_MONOTONIC = 1;
static const unsigned CLOCK_REALTIME_COARSE = 5;
static const unsigned CLOCK_MONOTONIC_COARSE = 6;
static const unsigned CLOCK_BOOTTIME = 7;

typedef int clockid_t;
typedef int64_t time_t;
typedef long suseconds_t;
typedef int64_t off_t;
typedef int pid_t;
typedef int mode_t;

struct timeval {
  time_t tv_sec;
  suseconds_t tv_usec;
};
struct timespec {
  time_t tv_sec;
  long tv_nsec;
};

struct tm {
  int tm_sec;
  int tm_min;
  int tm_hour;
  int tm_mday;
  int tm_mon;
  int tm_year;
  int tm_wday;
  int tm_yday;
  int tm_isdst;
};

typedef struct _iobuf FILE;

void *calloc(size_t, size_t);
void free(void *);
void *malloc(size_t);
void *realloc(void *, size_t);

int open(const char *, int, ...) __asm__("_open");
int close(int) __asm__("_close");
int read(int, void *, unsigned int) __asm__("_read");
int write(int, const void *, unsigned int) __asm__("_write");
off_t lseek(int, off_t, int) __asm__("_lseeki64");
int fsync(int) __asm__("_commit");
int fdatasync(int) __asm__("_commit");
int access(const char *, int) __asm__("_access");
int dup2(int, int) __asm__("_dup2");
int unlink(const char *) __asm__("_unlink");
int rmdir(const char *) __asm__("_rmdir");
pid_t getpid(void) __asm__("_getpid");
void _exit(int);

int fclose(FILE *);
int ferror(FILE *);
int fflush(FILE *);
int fileno(FILE *) __asm__("_fileno");
FILE *fopen(const char *, const char *);
int fputs(const char *, FILE *);
size_t fread(void *, size_t, size_t, FILE *);
size_t fwrite(const void *, size_t, size_t, FILE *);
int sprintf(char *, const char *, ...);

void *memchr(const void *, int, size_t);
int memcmp(const void *, const void *, size_t);
void *memmove(void *, const void *, size_t);
int strcasecmp(const char *, const char *) __asm__("_stricmp");
int strcmp(const char *, const char *);
int strcoll(const char *, const char *);
char *strdup(const char *) __asm__("_strdup");
char *strerror(int);
int strncasecmp(const char *, const char *, size_t) __asm__("_strnicmp");
size_t strnlen(const char *, size_t);

int _putenv_s(const char *, const char *);
int _set_fmode(int);
]]
