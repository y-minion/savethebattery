#include "MacBridge.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <unistd.h>
#include <signal.h>
#include <string.h>
#include <errno.h>
int vb_process(int32_t pid, VBProcess *out) {
    struct proc_bsdinfo b={0}; struct proc_taskinfo t={0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &b, sizeof(b)) != sizeof(b)) return 0;
    memset(out,0,sizeof(*out)); out->pid=pid; out->ppid=b.pbi_ppid; out->uid=b.pbi_uid;
    out->started=b.pbi_start_tvsec*1000000ULL+b.pbi_start_tvusec;
    strlcpy(out->name,b.pbi_name[0]?b.pbi_name:b.pbi_comm,sizeof(out->name));
    if (proc_pidinfo(pid,PROC_PIDTASKINFO,0,&t,sizeof(t)) == sizeof(t)) {
        out->cpu_ns=t.pti_total_user+t.pti_total_system; out->memory=t.pti_resident_size;
    }
    return 1;
}
int vb_pids(int32_t *out,int capacity) { int n=proc_listallpids(out,capacity*(int)sizeof(int32_t)); return n>capacity?capacity:n; }
int vb_signal(int32_t pid,uint64_t started,int sig) {
    if (pid<=1) return EPERM;
    VBProcess p;
    if (!vb_process(pid,&p)||p.started!=started||p.uid!=geteuid()) return ESRCH;
    int32_t ancestor=getpid();
    for(int i=0;i<128&&ancestor>1;i++) { if(ancestor==pid) return EPERM; VBProcess a; if(!vb_process(ancestor,&a)) break; ancestor=a.ppid; }
    return kill(pid,sig)==0?0:errno;
}
