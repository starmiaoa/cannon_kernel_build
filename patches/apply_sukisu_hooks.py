#!/usr/bin/env python3
"""Insert SukiSU tracepoint-hook calls into a 4.14 non-GKI kernel tree.

Run from the kernel source root AFTER `setup.sh` has vendored the SukiSU
driver into drivers/kernelsu. Aborts with a non-zero exit if any anchor is
missing or already patched, so a silently unpatched kernel cannot be built.
"""
import sys

GUARD = '#if defined(CONFIG_KSU) && defined(CONFIG_KSU_TRACEPOINT_HOOK)'
ENDIF = '#endif'


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


def call_block(call):
    return GUARD + '\n\t' + call + '\n' + ENDIF + '\n'


def include_block(include):
    return GUARD + '\n' + include + '\n' + ENDIF + '\n\n'


def insert_before(text, idx, block):
    return text[:idx] + block + text[idx:]


def patch_exec():
    path = 'fs/exec.c'
    text = load(path)
    if 'ksu_trace_execveat_hook' in text:
        die(path + ' already patched')
    anchor = 'static int do_execveat_common(int fd, struct filename *filename,'
    idx = find_from(text, anchor)
    # Place the include after `struct user_arg_ptr` is defined (it precedes
    # do_execveat_common) so the trace inline can reference the type.
    text = insert_before(text, idx,
                         include_block('#include <../drivers/kernelsu/ksu_trace.h>'))
    for name in ('int do_execve(struct filename *filename,',
                 'static int compat_do_execve(struct filename *filename,'):
        start = find_from(text, name)
        ret = find_from(text,
                        'return do_execveat_common(AT_FDCWD, filename, argv, envp, 0);',
                        start)
        text = insert_before(text, ret,
                             call_block('trace_ksu_trace_execveat_hook((int *)AT_FDCWD, '
                                        '&filename, &argv, &envp, 0);'))
    save(path, text)
    print('patched ' + path)


def patch_open():
    path = 'fs/open.c'
    text = load(path)
    if 'ksu_trace_faccessat_hook' in text:
        die(path + ' already patched')
    anchor = 'SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)'
    idx = find_from(text, anchor)
    text = insert_before(text, idx,
                         include_block('#include <../drivers/kernelsu/ksu_trace.h>'))
    start = find_from(text, anchor)
    # 4.14 inlines the faccessat body in the syscall itself; the hook goes
    # after the last declaration because the kernel builds with -std=gnu89.
    decl = find_from(text, 'unsigned int lookup_flags = LOOKUP_FOLLOW;', start)
    eol = text.find('\n', decl)
    if eol < 0:
        die('cannot find end of lookup_flags declaration')
    block = GUARD + '\n\ttrace_ksu_trace_faccessat_hook(&dfd, &filename, &mode, NULL);\n' + ENDIF + '\n'
    text = text[:eol + 1] + block + text[eol + 1:]
    save(path, text)
    print('patched ' + path)


def patch_read():
    path = 'fs/read_write.c'
    text = load(path)
    if 'ksu_trace_sys_read_hook' in text:
        die(path + ' already patched')
    anchor = 'SYSCALL_DEFINE3(read, unsigned int, fd, char __user *, buf, size_t, count)'
    idx = find_from(text, anchor)
    text = insert_before(text, idx,
                         include_block('#include <../drivers/kernelsu/ksu_trace.h>'))
    start = find_from(text, anchor)
    ret = find_from(text, 'ret = vfs_read(f.file, buf, count, &pos);', start)
    text = insert_before(text, ret,
                         call_block('trace_ksu_trace_sys_read_hook(fd, &buf, &count);'))
    save(path, text)
    print('patched ' + path)


def patch_stat():
    path = 'fs/stat.c'
    text = load(path)
    if 'ksu_trace_stat_hook' in text:
        die(path + ' already patched')
    anchor = 'SYSCALL_DEFINE4(newfstatat, int, dfd, const char __user *, filename,'
    idx = find_from(text, anchor)
    text = insert_before(text, idx,
                         include_block('#include <../drivers/kernelsu/ksu_trace.h>'))
    start = find_from(text, anchor)
    ret = find_from(text, 'error = vfs_fstatat(dfd, filename, &stat, flag);', start)
    text = insert_before(text, ret,
                         call_block('trace_ksu_trace_stat_hook(&dfd, &filename, &flag);'))
    anchor64 = 'SYSCALL_DEFINE4(fstatat64, int, dfd, const char __user *, filename,'
    start = find_from(text, anchor64)
    ret = find_from(text, 'error = vfs_fstatat(dfd, filename, &stat, flag);', start)
    text = insert_before(text, ret,
                         call_block('trace_ksu_trace_stat_hook(&dfd, &filename, &flag); '
                                    '/* 32-bit su support */'))
    save(path, text)
    print('patched ' + path)


def patch_input():
    path = 'drivers/input/input.c'
    text = load(path)
    if 'ksu_trace_input_hook' in text:
        die(path + ' already patched')
    anchor = 'MODULE_AUTHOR("Vojtech Pavlik <vojtech@suse.cz>");'
    idx = find_from(text, anchor)
    text = insert_before(text, idx,
                         include_block('#include <../../drivers/kernelsu/ksu_trace.h>'))
    start = find_from(text, 'void input_event(struct input_dev *dev,')
    flags = find_from(text, 'unsigned long flags;', start)
    eol = text.find('\n', flags)
    if eol < 0:
        die('cannot find end of flags declaration in input.c')
    block = GUARD + '\n\ttrace_ksu_trace_input_hook(&type, &code, &value);\n' + ENDIF + '\n'
    text = text[:eol + 1] + block + text[eol + 1:]
    save(path, text)
    print('patched ' + path)


def main():
    import os
    if not os.path.exists('drivers/kernelsu/ksu_trace.h'):
        die('drivers/kernelsu/ksu_trace.h missing - run SukiSU setup.sh first')
    patch_exec()
    patch_open()
    patch_read()
    patch_stat()
    patch_input()
    print('all SukiSU tracepoint hooks inserted')


if __name__ == '__main__':
    main()
