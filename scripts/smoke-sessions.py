#!/usr/bin/env python3
"""Controlled integration tests: only disposable processes started here are used."""
import json, os, pathlib, signal, subprocess, sys, tempfile, time
binary=str(pathlib.Path(sys.argv[1] if len(sys.argv)>1 else '.build/debug/stb').resolve())
with tempfile.TemporaryDirectory(prefix='savethebattery-test-') as root:
    env={**os.environ,'STB_DATA_DIR':root,'STB_LANG':'en'}
    def run(*args): return subprocess.run([binary,*args],env=env,capture_output=True,text=True,timeout=20)
    def records(): return [json.loads(f.read_text()) for f in pathlib.Path(root,'sessions').glob('*.json')]
    r=run('run','--allow-battery','--','/bin/echo','hello world','$(touch not-executed)')
    assert r.returncode==0 and '$(touch not-executed)' in r.stdout, r.stderr
    assert not pathlib.Path('not-executed').exists()
    assert run('run','--allow-battery','--','/bin/sh','-c','exit 7').returncode==7
    r=run('run','--allow-battery','--hours','0.00005','--','/bin/sleep','0.3')
    assert r.returncode==0 and any(x['outcome']=='expired' for x in records()), 'deadline must win over completion between polls'
    p=subprocess.Popen([binary,'run','--allow-battery','--','/bin/sleep','2'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
    line=p.stderr.readline(); sid=line.split('Session ')[1].split(' ')[0]
    assert run('release',sid).returncode==0
    time.sleep(.7); assert p.poll() is None, 'release killed the task'
    assert p.wait(timeout=5)==0
    # Cancellation releases only its own assertion even when the child ignores TERM.
    ignored=pathlib.Path(root,'ignored.ready')
    code='import signal,time,pathlib;signal.signal(signal.SIGTERM,signal.SIG_IGN);pathlib.Path('+repr(str(ignored))+').touch();time.sleep(3)'
    a=subprocess.Popen([binary,'run','--allow-battery','--cleanup','--',sys.executable,'-c',code],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
    aid=a.stderr.readline().split('Session ')[1].split(' ')[0]
    b=subprocess.Popen([binary,'run','--allow-battery','--','/bin/sleep','3'],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
    bid=b.stderr.readline().split('Session ')[1].split(' ')[0]
    deadline=time.monotonic()+3
    while not ignored.exists() and time.monotonic()<deadline: time.sleep(.02)
    assert ignored.exists()
    assertions=subprocess.check_output(['/usr/bin/pmset','-g','assertions'],text=True)
    assert 'pid '+str(a.pid)+'(' in assertions and 'pid '+str(b.pid)+'(' in assertions
    a.send_signal(signal.SIGTERM);time.sleep(.7)
    by_id={x['id']:x for x in records()}
    assert not by_id[aid]['protected'] and by_id[aid]['cleanup']=='observe' and by_id[aid]['outcome']=='cancelled'
    assert by_id[bid]['protected'] and a.poll() is None and b.poll() is None
    assertions=subprocess.check_output(['/usr/bin/pmset','-g','assertions'],text=True)
    assert 'pid '+str(a.pid)+'(' not in assertions and 'pid '+str(b.pid)+'(' in assertions
    assert a.wait(timeout=5)==0 and b.wait(timeout=5)==0
    # A temporary registered resource is stopped only following successful completion.
    pidfile=pathlib.Path(root,'child.pid')
    code='import os,time;open('+repr(str(pidfile))+',"w").write(str(os.getpid()));time.sleep(20)'
    env['STB_TEST_BINARY']=binary;env['STB_TEST_PYTHON']=sys.executable;env['STB_TEST_CODE']=code
    command='"$STB_TEST_BINARY" resource -- "$STB_TEST_PYTHON" -c "$STB_TEST_CODE" >/dev/null 2>&1 & sleep 1'
    r=subprocess.run([binary,'run','--allow-battery','--cleanup','--','/bin/sh','-c',command],env=env,capture_output=True,text=True,timeout=10)
    assert r.returncode==0, r.stderr
    child=int(pidfile.read_text()); deadline=time.monotonic()+5
    while time.monotonic()<deadline:
        try: os.kill(child,0)
        except ProcessLookupError: break
        time.sleep(.1)
    else:
        os.kill(child,signal.SIGTERM);raise AssertionError('registered resource not cleaned up')
    # Failure and --keep preserve temporary children until their natural exit.
    for keep,exit_code in [(False,7),(True,0)]:
        ready=pathlib.Path(root,'preserved-'+str(exit_code)+'.ready')
        finished=pathlib.Path(root,'preserved-'+str(exit_code)+'.finished')
        code='import pathlib,time;pathlib.Path('+repr(str(ready))+').touch();time.sleep(2);pathlib.Path('+repr(str(finished))+').touch()'
        env['STB_TEST_CODE']=code;env['STB_TEST_READY']=str(ready)
        resource='"$STB_TEST_BINARY" resource '+('--keep ' if keep else '')+'-- "$STB_TEST_PYTHON" -c "$STB_TEST_CODE" >/dev/null 2>&1 & '
        command=resource+'while [ ! -f "$STB_TEST_READY" ]; do sleep 0.02; done; exit '+str(exit_code)
        r=subprocess.run([binary,'run','--allow-battery','--cleanup','--','/bin/sh','-c',command],env=env,capture_output=True,text=True,timeout=10)
        assert r.returncode==exit_code,r.stderr
        deadline=time.monotonic()+5
        while not finished.exists() and time.monotonic()<deadline: time.sleep(.05)
        assert finished.exists(),'failure or --keep incorrectly terminated a resource'
    print('PASS: argv, exit status, expiry, release, cancellation, concurrent assertions, scoped cleanup, failure/keep preservation')
