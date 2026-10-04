"""The public-to-private invite transition must update iOS sharing exactly once."""
from pathlib import Path
import os, re, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / 'port/linux/src/p2p.c').read_text(encoding='utf-8')
function = source.split('void p2p_new_invite_if_listed(void)\n', 1)[1].split('\n/* the hosted game', 1)[0]
assert 'host_active_invite(p2p.invite)' in function
build = (ROOT / 'tools/android_build.py').read_text(encoding='utf-8')
assert '"monocypher.c", "monocypher-ed25519.c"' in build
assert 'f"-I{MONOCYPHER_DIR}"' in build
assert 'sorted((LINUX_DIR / "src").glob("*.c"))' in build
code = r'''
#include <assert.h>
#include <string.h>
#define HALO_IOS_GUEST 1
static struct { int has_token, token_listed, hosting, has_clipboard, reported_player_count; char invite[80], clipboard[80]; unsigned char token[16]; } p2p;
static int made, shared, signalled;
static char active[80];
static void make_invite(void) { made++; p2p.token_listed=0; strcpy(p2p.invite,"halo://join/new-private-code"); }
static void platform_log(const char *format, ...) { (void)format; }
static void p2p_signal_host(const unsigned char *token) { (void)token; signalled++; }
static void host_active_invite(const char *text) { shared++; strcpy(active,text); }
void p2p_new_invite_if_listed(void)
''' + function + r'''
int main(void) {
 p2p_new_invite_if_listed(); assert(!made && !shared && !signalled);
 p2p.has_token=1; p2p_new_invite_if_listed(); assert(!made && !shared);
 p2p.token_listed=1; p2p.hosting=1; p2p_new_invite_if_listed();
 assert(made==1 && shared==1 && signalled==1);
 assert(!strcmp(active,p2p.invite) && !strcmp(p2p.clipboard,p2p.invite));
 assert(p2p.has_clipboard && p2p.reported_player_count==-1);
 p2p_new_invite_if_listed(); assert(made==1 && shared==1 && signalled==1);
 p2p.token_listed=1; p2p.hosting=0; p2p_new_invite_if_listed();
 assert(made==2 && shared==1 && signalled==1);
 return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
 path=Path(tmp); c=path/'invite.c'; exe=path/'invite.exe'; c.write_text(code,encoding='utf-8')
 cc=os.environ.get('CC','cc')
 if Path(cc).stem.lower()=='cl':
  command=[cc,'/nologo','/std:c11','/D_CRT_SECURE_NO_WARNINGS','/W4','/WX',str(c),f'/Fe{exe}',f'/Fo{path}/']
 else:
  command=[cc,'-std=c11','-Wall','-Wextra','-Werror',str(c),'-o',str(exe)]
 subprocess.run(command,check=True)
 subprocess.run([str(exe)],check=True)
print('PASS: public/private invite rotation updates iOS sharing once; guest signing sources are included')
