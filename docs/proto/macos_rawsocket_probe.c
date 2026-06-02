#include <stdint.h>
static long sys3(long n,long a,long b,long c){
  register long x16 asm("x16")=n; register long x0 asm("x0")=a;
  register long x1 asm("x1")=b; register long x2 asm("x2")=c;
  asm volatile("svc #0x80":"+r"(x0):"r"(x16),"r"(x1),"r"(x2):"cc","memory");
  return x0;
}
#define SC 0x2000000L
struct sa{uint8_t len;uint8_t fam;uint16_t port;uint32_t addr;uint8_t z[8];};
int main(void){
  long fd=sys3(SC|97,2,1,0);                 // socket(AF_INET,SOCK_STREAM,0)
  struct sa a; for(int i=0;i<16;i++)((char*)&a)[i]=0;
  a.len=16; a.fam=2; a.port=(8090>>8)|((8090&0xff)<<8); a.addr=0;
  long b=sys3(SC|104,fd,(long)&a,16);        // bind
  long l=sys3(SC|106,fd,16,0);               // listen
  const char* m="RAWSOCK fd=%ld bind=%ld listen=%ld\n";
  // print via raw write (build the line manually-ish)
  char buf[64]; int p=0; const char* s="RAWSOCK ready\n"; while(s[p]){buf[p]=s[p];p++;}
  sys3(SC|4,1,(long)buf,p);
  long cl=sys3(SC|30,fd,0,0);                 // accept (blocks)
  const char* r="HTTP/1.1 200 OK\r\nContent-Length:13\r\n\r\nhello rawsock";
  int L=0; while(r[L])L++;
  sys3(SC|4,cl,(long)r,L);                    // write response
  sys3(SC|6,cl,0,0); sys3(SC|6,fd,0,0);       // close
  return 0;
}
