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
