#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>

typedef struct ABlock { struct ABlock* next; int cap; int used; } ABlock;
static ABlock* _arena = 0;
static char* _alloc(int n) {
    n = (n+7)&~7;
    if (!_arena || _arena->used+n > _arena->cap) {
        int cap = 64*1024*1024;
        if (n > cap) cap = n;
        ABlock* b = (ABlock*)malloc(sizeof(ABlock)+cap);
        if (!b) { fprintf(stderr,"out of memory\n"); exit(1); }
        b->cap=cap; b->used=0; b->next=_arena; _arena=b;
    }
    char* p = (char*)(_arena+1)+_arena->used;
    _arena->used += n;
    return p;
}

static char _K_EMPTY[]=""; static char _K_ZERO[]="0"; static char _K_ONE[]="1";

char* kr_str(const char* s) {
    if (!s||!*s) return _K_EMPTY;
    if (s[0]=='0'&&!s[1]) return _K_ZERO;
    if (s[0]=='1'&&!s[1]) return _K_ONE;
    int n=strlen(s)+1; char* p=_alloc(n); memcpy(p,s,n); return p;
}
char* kr_cat(const char* a,const char* b) {
    int la=strlen(a),lb=strlen(b); char* p=_alloc(la+lb+1);
    memcpy(p,a,la); memcpy(p+la,b,lb+1); return p;
}
static int kr_isnum(const char* s) {
    if (!*s) return 0; const char* p=s; if (*p=='-') p++;
    if (!*p) return 0; while (*p){if (*p<'0'||*p>'9')return 0;p++;} return 1;
}
static char* kr_itoa(int v) {
    if (v==0) return _K_ZERO; if (v==1) return _K_ONE;
    char buf[32]; snprintf(buf,sizeof(buf),"%d",v); return kr_str(buf);
}
char* kr_plus(const char* a,const char* b) {
    if (kr_isnum(a)&&kr_isnum(b)) return kr_itoa(atoi(a)+atoi(b));
    return kr_cat(a,b);
}
char* kr_sub(const char* a,const char* b){return kr_itoa(atoi(a)-atoi(b));}
char* kr_mul(const char* a,const char* b){return kr_itoa(atoi(a)*atoi(b));}
char* kr_div(const char* a,const char* b){return kr_itoa(atoi(b)?atoi(a)/atoi(b):0);}
char* kr_mod(const char* a,const char* b){return kr_itoa(atoi(b)?atoi(a)%atoi(b):0);}
char* kr_neg(const char* a){return kr_itoa(-atoi(a));}
char* kr_not(const char* a){return atoi(a)?_K_ZERO:_K_ONE;}
char* kr_eq(const char* a,const char* b){return strcmp(a,b)==0?_K_ONE:_K_ZERO;}
char* kr_neq(const char* a,const char* b){return strcmp(a,b)!=0?_K_ONE:_K_ZERO;}
char* kr_lt(const char* a,const char* b){
    if(kr_isnum(a)&&kr_isnum(b))return atoi(a)<atoi(b)?_K_ONE:_K_ZERO;
    return strcmp(a,b)<0?_K_ONE:_K_ZERO;}
char* kr_gt(const char* a,const char* b){
    if(kr_isnum(a)&&kr_isnum(b))return atoi(a)>atoi(b)?_K_ONE:_K_ZERO;
    return strcmp(a,b)>0?_K_ONE:_K_ZERO;}
char* kr_lte(const char* a,const char* b){return kr_gt(a,b)==_K_ZERO?_K_ONE:_K_ZERO;}
char* kr_gte(const char* a,const char* b){return kr_lt(a,b)==_K_ZERO?_K_ONE:_K_ZERO;}
int   kr_truthy(const char* s){if(!s||!*s)return 0;if(strcmp(s,"0")==0)return 0;return 1;}
char* kr_print(const char* s){printf("%s\n",s);return _K_EMPTY;}
char* kr_kp(const char* s){printf("%s\n",s);return _K_EMPTY;}
char* kr_len(const char* s){return kr_itoa((int)strlen(s));}
char* kr_toInt(const char* s){return kr_itoa(atoi(s));}
char* kr_contains(const char* s,const char* sub){return strstr(s,sub)?_K_ONE:_K_ZERO;}
char* kr_startsWith(const char* s,const char* pre){return strncmp(s,pre,strlen(pre))==0?_K_ONE:_K_ZERO;}
char* kr_fadd(const char* a,const char* b){char buf[64];snprintf(buf,64,"%g",atof(a)+atof(b));return kr_str(buf);}
char* kr_fsub(const char* a,const char* b){char buf[64];snprintf(buf,64,"%g",atof(a)-atof(b));return kr_str(buf);}
char* kr_fmul(const char* a,const char* b){char buf[64];snprintf(buf,64,"%g",atof(a)*atof(b));return kr_str(buf);}
char* kr_fdiv(const char* a,const char* b){char buf[64];if(atof(b)==0.0)return _K_ZERO;snprintf(buf,64,"%g",atof(a)/atof(b));return kr_str(buf);}
char* kr_fsqrt(const char* a){char buf[64];snprintf(buf,64,"%g",sqrt(atof(a)));return kr_str(buf);}
char* kr_flt(const char* a,const char* b){return atof(a)<atof(b)?_K_ONE:_K_ZERO;}
char* kr_fgt(const char* a,const char* b){return atof(a)>atof(b)?_K_ONE:_K_ZERO;}

extern char* __main__(void);
int main(int argc,char** argv){__main__();return 0;}
