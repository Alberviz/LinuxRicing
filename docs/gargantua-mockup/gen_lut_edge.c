// gen_lut_edge.c — port a C de gen_lut_final.py (geodésica nula de Schwarzschild) con la
// cámara casi de canto: THETA0=acos(0.06) (~3.4° sobre el plano), R_OUTER=10, RHO_MAX=12.
// (El entorno no tiene numpy, por eso C+OpenMP: N=2048 en ~1 min en vez de 15-30.)
// Salida (RGBA8, A=255): lut_edge_order{0,1}_r.ppm-like raw → convertido por gen_lut_edge.py
//   r.png : R=radio hi, G=radio lo (16 bits, 0 = sin cruce), B=0
//   az.png: R=azimut hi, G=azimut lo (16 bits), B=0
// Uso:  gcc -O3 -fopenmp -o gen_lut_edge gen_lut_edge.c -lm && ./gen_lut_edge && python3 gen_lut_edge.py
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#define N 2048
#define RHO_MAX 12.0
#define M 0.5
static const double R_HORIZON=1.0, R_ISCO=1.18, R_OUTER=10.0;
static double THETA0;
static double f(double u){ return -u + 3.0*M*u*u; }
int main(void){
    THETA0 = acos(0.06);
    double s0=sin(THETA0), c0=cos(THETA0);
    uint16_t *out[4];
    for(int i=0;i<4;i++) out[i]=calloc((size_t)N*N,2);   // r0,az0,r1,az1
    #pragma omp parallel for schedule(dynamic,4)
    for(int j=0;j<N;j++){
      for(int i=0;i<N;i++){
        double px=-RHO_MAX+2*RHO_MAX*i/(N-1), py=-RHO_MAX+2*RHO_MAX*j/(N-1);
        double rho=hypot(px,py), xi=atan2(px,py);
        double b=fmax(rho,1e-6);
        double A=cos(THETA0), Bc=cos(xi)*s0;
        double phi0=atan2(-A,Bc); if(phi0<=1e-9) phi0+=M_PI;
        double tg[2]={phi0,phi0+M_PI};
        double u=0,up=1.0/b,phi=0,dphi=0.0008, phimax=3.4*M_PI;
        int nst=(int)(phimax/dphi);
        int started=0,rec[2]={0,0};
        double rr[2]={0,0},th[2]={0,0};
        double pu=u,pphi=phi;
        for(int st=0;st<nst;st++){
            if(u>1e-6) started=1;
            if(u>=1.0) break;
            if(started && u<=0.0 && up<0.0) break;
            for(int o=0;o<2;o++){
                if(!rec[o] && phi>=tg[o] && pphi<tg[o]){
                    double t=(tg[o]-pphi)/(phi>pphi?phi-pphi:1.0);
                    double ua=pu+t*(u-pu);
                    rr[o]= ua>1e-9 ? 1.0/ua : NAN;
                    double cp=cos(tg[o]),sp=sin(tg[o]),cx=cos(xi),sx=sin(xi);
                    th[o]=atan2(sp*(-sx), cp*s0+sp*(-cx*c0));
                    rec[o]=1;
                }
            }
            pu=u;pphi=phi;
            double k1u=up,k1p=f(u);
            double k2u=up+0.5*dphi*k1p,k2p=f(u+0.5*dphi*k1u);
            double k3u=up+0.5*dphi*k2p,k3p=f(u+0.5*dphi*k2u);
            double k4u=up+dphi*k3p,k4p=f(u+dphi*k3u);
            u+=dphi/6*(k1u+2*k2u+2*k3u+k4u);
            up+=dphi/6*(k1p+2*k2p+2*k3p+k4p);
            phi+=dphi;
        }
        for(int o=0;o<2;o++){
            if(rec[o] && rr[o]==rr[o] && rr[o]>=R_ISCO*0.98 && rr[o]<=R_OUTER){
                double rn=(rr[o]-R_HORIZON)/(R_OUTER-R_HORIZON);
                uint32_t r16=(uint32_t)fmin(65535.0,fmax(1.0,round(rn*65535.0)));
                double tn=(th[o]+M_PI)/(2*M_PI); tn=fmin(1,fmax(0,tn));
                out[2*o][(size_t)j*N+i]=r16;
                out[2*o+1][(size_t)j*N+i]=(uint16_t)round(tn*65535.0);
            }
        }
      }
    }
    const char*nm[4]={"o0_r","o0_az","o1_r","o1_az"};
    for(int k=0;k<4;k++){ char p[64]; snprintf(p,64,"lut_edge_%s.raw",nm[k]); FILE*fp=fopen(p,"wb"); fwrite(out[k],2,(size_t)N*N,fp); fclose(fp);}
    return 0;
}
