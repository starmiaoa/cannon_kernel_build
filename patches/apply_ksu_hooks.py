#!/usr/bin/env python3
"""Insert KernelSU v0.9.5 manual hooks into a 4.14 non-GKI kernel tree.

Ported from the gtcock/android_kernel_xiaomi_cannon ksu branch, which runs
this exact integration on a cannon 4.14 kernel. Run from the kernel source
root AFTER drivers/kernelsu has been vendored. Aborts non-zero if any anchor
is missing or already patched.
"""
import sys

EXEC_EXTERNS = '''\
#ifdef CONFIG_KSU
extern bool ksu_execveat_hook;
extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);
extern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);
#endif

'''

EXEC_HOOK = '''\
#ifdef CONFIG_KSU
\tif (unlikely(ksu_execveat_hook))
\t\tksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);
\telse
\t\tksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);
#endif
'''

FACCESSAT_EXTERNS = '''\
#ifdef CONFIG_KSU
extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *flags);
#endif

'''

FACCESSAT_HOOK = '''\
\t#ifdef CONFIG_KSU
\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);
\t#endif
'''

STAT_EXTERNS = '''\
#ifdef CONFIG_KSU
extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);
#endif

'''

STAT_HOOK = '''\
\t#ifdef CONFIG_KSU
\tksu_handle_stat(&dfd, &filename, &flags);
\t#endif
'''


def load(path):
    with open(path, encoding='utf-8', errors='surrogateescape') as f:
        return f.read()


def save(path, text):
    with open(path, 'w', encoding='utf-8', errors='surrogateescape') as f:
        f.write(text)


def die(msg):
    print('PATCH ERROR: ' + msg)
    sys.exit(1)


def find_from(text, anchor, pos=0):
    i = text.find(anchor, pos)
    if i < 0:
        die('anchor not found: %r' % anchor[:80])
    return i


def insert_before(text, idx, block):
    return text[:idx] + block + text[idx:]


def insert_after_eol(text, idx, block):
    eol = text.find('\n', idx)
    if eol < 0:
        die('no newline after anchor at %d' % idx)
    return text[:eol + 1] + block + text[eol + 1:]


def patch_exec():
    path = 'fs/exec.c'
    text = load(path)
    if 'ksu_handle_execveat' in text:
        die(path + ' already patched')
    # extern declarations at top level, after user_arg_ptr is defined
    anchor = 'static int do_execveat_common(int fd, struct filename *filename,'
    idx = find_from(text, anchor)
    text = insert_before(text, idx, EXEC_EXTERNS)
    # hook inside do_execveat_common, after the filename error check
    start = find_from(text, anchor)
    err = find_from(text, 'if (IS_ERR(filename))', start)
    err_ret = find_from(text, 'return PTR_ERR(filename);', err)
    text = insert_after_eol(text, err_ret, EXEC_HOOK)
    save(path, text)
    print('patched ' + path)


def patch_open():
    path = 'fs/open.c'
    text = load(path)
    if 'ksu_handle_faccessat' in text:
        die(path + ' already patched')
    anchor = '#include "internal.h"'
    idx = find_from(text, anchor)
    text = insert_after_eol(text, idx, FACCESSAT_EXTERNS)
    # hook after the last declaration of the faccessat syscall body; the
    # kernel builds with -std=gnu89 so this stays warning-free.
    start = find_from(text, 'SYSCALL_DEFINE3(faccessat, int, dfd, '
                            'const char __user *, filename, int, mode)')
    decl = find_from(text, 'unsigned int lookup_flags = LOOKUP_FOLLOW;', start)
    text = insert_after_eol(text, decl, FACCESSAT_HOOK)
    save(path, text)
    print('patched ' + path)


def patch_stat():
    path = 'fs/stat.c'
    text = load(path)
    if 'ksu_handle_stat' in text:
        die(path + ' already patched')
    anchor = '#include <asm/unistd.h>'
    idx = find_from(text, anchor)
    text = insert_after_eol(text, idx, STAT_EXTERNS)
    # vfs_statx serves stat/fstatat/statx (incl. compat), so one hook at its
    # top covers every stat flavour; place it after the declarations.
    start = find_from(text, 'int vfs_statx(int dfd, const char __user *filename, int flags,')
    decl = find_from(text,
                     'unsigned int lookup_flags = LOOKUP_FOLLOW | LOOKUP_AUTOMOUNT;',
                     start)
    text = insert_after_eol(text, decl, STAT_HOOK)
    save(path, text)
    print('patched ' + path)


def main():
    import os
    if not os.path.exists('drivers/kernelsu/Kconfig'):
        die('drivers/kernelsu/Kconfig missing - vendor KernelSU first')
    patch_exec()
    patch_open()
    patch_stat()
    print('all KernelSU manual hooks inserted')


if __name__ == '__main__':
    main()
