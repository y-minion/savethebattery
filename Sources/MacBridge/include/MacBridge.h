#pragma once
#include <stdint.h>
typedef struct { int32_t pid, ppid; uint32_t uid; uint64_t started, cpu_ns, memory; char name[64]; } VBProcess;
int vb_process(int32_t pid, VBProcess *out);
int vb_pids(int32_t *out, int capacity);
int vb_signal(int32_t pid, uint64_t started, int signal_number);
int vb_spawn(char *const argv[], char *const env[], int32_t *pid);
int vb_wait(int32_t pid, int32_t *status);
void vb_watch_signals(void);
int vb_take_signal(void);
typedef struct { int32_t supported, enabled, limit; } VBChargeLimit;
// 0 ok, -1 PowerUI unavailable, -2 rejected by macOS, -3 out of range.
int vb_mcl_read(VBChargeLimit *out);
int vb_mcl_set_limit(int32_t percent);
int vb_mcl_top_up(void);
int vb_mcl_enable(void);
int vb_mcl_disable(void);
int vb_pid_path(int32_t pid, char *buffer, int size);
int vb_notify(const char *name);
