-- Quarry C foreign function interface configuration
-- Comprehensive POSIX, standard library, and runtime bindings.

local ffi = {}

ffi.C = terralib.includecstring [[
    typedef unsigned long size_t;
    typedef long ssize_t;
    typedef long off_t;
    typedef int mode_t;
    typedef unsigned int uint32_t;
    typedef unsigned long uint64_t;
    typedef int int32_t;
    typedef long int64_t;

    // Standard I/O
    int printf(const char *format, ...);
    int snprintf(char *str, size_t size, const char *format, ...);
    int sprintf(char *str, const char *format, ...);
    int puts(const char *s);
    int putchar(int c);

    // Memory management
    void *malloc(size_t size);
    void *calloc(size_t count, size_t size);
    void *realloc(void *ptr, size_t size);
    void free(void *ptr);
    int posix_memalign(void **memptr, size_t alignment, size_t size);
    void *memset(void *b, int c, size_t len);
    void *memcpy(void *dst, const void *src, size_t len);
    void *memmove(void *dst, const void *src, size_t len);
    int memcmp(const void *s1, const void *s2, size_t n);

    // String manipulation
    size_t strlen(const char *s);
    int strcmp(const char *s1, const char *s2);
    int strncmp(const char *s1, const char *s2, size_t n);
    char *strdup(const char *s1);
    char *strcpy(char *dst, const char *src);
    char *strncpy(char *dst, const char *src, size_t len);
    char *strcat(char *s1, const char *s2);
    char *strncat(char *s1, const char *s2, size_t n);
    char *strchr(const char *s, int c);
    char *strstr(const char *haystack, const char *needle);
    double strtod(const char *str, char **endptr);
    long strtol(const char *str, char **endptr, int base);
    long long strtoll(const char *str, char **endptr, int base);

    // Math functions
    double sqrt(double x);
    float sqrtf(float x);
    double pow(double x, double y);
    double exp(double x);
    double log(double x);
    double log2(double x);
    double fabs(double x);
    float fabsf(float x);
    double floor(double x);
    double ceil(double x);
    double sin(double x);
    double cos(double x);

    // POSIX file operations and memory mapping
    int open(const char *path, int oflag, ...);
    int close(int fd);
    ssize_t read(int fd, void *buf, size_t nbyte);
    ssize_t write(int fd, const void *buf, size_t nbyte);
    off_t lseek(int fd, off_t offset, int whence);
    void *mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset);
    int munmap(void *addr, size_t len);
    int madvise(void *addr, size_t len, int behav);

    // POSIX Threads
    typedef void *pthread_t;
    typedef struct { long __sig; char __opaque[56]; } pthread_mutex_t;
    typedef struct { long __sig; char __opaque[40]; } pthread_cond_t;
    typedef struct { long __sig; char __opaque[192]; } pthread_rwlock_t;

    int pthread_create(pthread_t *thread, const void *attr, void *(*start_routine)(void *), void *arg);
    int pthread_join(pthread_t thread, void **retval);
    int pthread_detach(pthread_t thread);
    pthread_t pthread_self(void);

    int pthread_mutex_init(pthread_mutex_t *mutex, const void *attr);
    int pthread_mutex_lock(pthread_mutex_t *mutex);
    int pthread_mutex_trylock(pthread_mutex_t *mutex);
    int pthread_mutex_unlock(pthread_mutex_t *mutex);
    int pthread_mutex_destroy(pthread_mutex_t *mutex);

    int pthread_cond_init(pthread_cond_t *cond, const void *attr);
    int pthread_cond_wait(pthread_cond_t *cond, pthread_mutex_t *mutex);
    int pthread_cond_signal(pthread_cond_t *cond);
    int pthread_cond_broadcast(pthread_cond_t *cond);
    int pthread_cond_destroy(pthread_cond_t *cond);

    // High resolution time
    struct timespec {
        long tv_sec;
        long tv_nsec;
    };
    int clock_gettime(int clk_id, struct timespec *tp);
    unsigned int sleep(unsigned int seconds);
    int usleep(unsigned int usec);

    // Sockets for embedded server
    int socket(int domain, int type, int protocol);
    int bind(int socket, const void *address, unsigned int address_len);
    int listen(int socket, int backlog);
    int accept(int socket, void *address, unsigned int *address_len);
    int setsockopt(int socket, int level, int option_name, const void *option_value, unsigned int option_len);
    int fcntl(int fd, int cmd, ...);
]]

return ffi
