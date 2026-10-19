#pragma once
#include <stdint.h>
typedef struct { int32_t pid, ppid; uint32_t uid; uint64_t started, cpu_ns, memory; char name[64]; } VBProcess;
int vb_process(int32_t pid, VBProcess *out);
int vb_pids(int32_t *out, int capacity);
int vb_signal(int32_t pid, uint64_t started, int signal_number);
