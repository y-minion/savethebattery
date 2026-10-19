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
    // Only the single-threaded supervisor's unreaped child has a reserved PID.
    // Never use this interface for arbitrary process-list selections.
    if (p.ppid != getpid()) return EPERM;
    return kill(pid,sig)==0?0:errno;
}
#include <spawn.h>
#include <sys/wait.h>
static volatile sig_atomic_t pending_signal=0;
static void receive_signal(int sig) { pending_signal=sig; }
void vb_watch_signals(void) { struct sigaction a={0};a.sa_handler=receive_signal;sigemptyset(&a.sa_mask);sigaction(SIGINT,&a,0);sigaction(SIGTERM,&a,0);sigaction(SIGHUP,&a,0); }
int vb_take_signal(void) { int s=pending_signal;pending_signal=0;return s; }
int vb_spawn(char *const argv[],char *const env[],int32_t *pid) {
    posix_spawnattr_t attr;posix_spawnattr_init(&attr);
    sigset_t defaults;sigemptyset(&defaults);sigaddset(&defaults,SIGINT);sigaddset(&defaults,SIGTERM);sigaddset(&defaults,SIGHUP);
    posix_spawnattr_setsigdefault(&attr,&defaults);posix_spawnattr_setflags(&attr,POSIX_SPAWN_SETSIGDEF);
    int r=posix_spawnp(pid,argv[0],NULL,&attr,argv,env);posix_spawnattr_destroy(&attr);return r;
}
int vb_wait(int32_t pid,int32_t *status) {
    int raw;pid_t r=waitpid(pid,&raw,WNOHANG);
    if(r==0) return 0;
    if(r<0) return errno==EINTR?0:-1;
    *status=WIFEXITED(raw)?WEXITSTATUS(raw):128+WTERMSIG(raw);return 1;
}
