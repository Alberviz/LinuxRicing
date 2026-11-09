#version 440
// whitehole.frag — agujero BLANCO = Gargantua inversa: el gemelo exacto del negro (portals/shaders/portal.frag) dado
// la vuelta. Núcleo incandescente donde el negro tiene la sombra; disco fino inclinado -17° frío con Doppler (gira al
// revés); halo lensado sobre el núcleo; corrientes en espiral que SALEN (grumos calientes cerca, fríos lejos); anillo
// de fotones; en cada expulsión (pulse 1 -> 0) ondas, destello y chispas; al cerrarse (closing 1 -> 0) un último
// destello de colapso. Portado 1:1 del mockup aprobado por Alberto (variante A). Procedural, sin partículas en CPU.
// Recompilar: /usr/lib/qt6/bin/qsb --qt6 -o whitehole.frag.qsb whitehole.frag
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  size;     // px del quad (centrado en el agujero)
    float rad;      // radio del núcleo en px
    float upx;      // px por «px de mockup» (ancho/1280)
    float en;       // energía 0..1 (respira; sube en cada expulsión)
    float vis;      // presencia 0..1
    float pulse;    // 1 -> 0: expulsión
    float spin;     // fase acumulada del disco
    float pull;     // fase acumulada de la eyección
    float tsec;     // tiempo en s (granulado y chispas)
    float closing;  // 1 -> 0: destello de colapso
};
#define R rad
#define U upx
float sm(float a,float b,float x){float t=clamp((x-a)/(b-a),0.,1.);return t*t*(3.-2.*t);}
float h11(float n){return fract(sin(n*127.1)*43758.5453);}
float h21(vec2 p){p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y);}
float vn(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);
 return mix(mix(h21(i),h21(i+vec2(1,0)),f.x),mix(h21(i+vec2(0,1)),h21(i+vec2(1,1)),f.x),f.y);}
float fbm(vec2 p){float a=.5,s=0.;for(int i=0;i<4;i++){s+=a*vn(p);p*=2.03;a*=.5;}return s;}
// partículas procedurales que salen del núcleo (sin CPU): n sectores, 3 capas
float sparks(vec2 s,float t,float n,float spread,float speed,float cone){
 float acc=0.;float r=length(s);float ang=atan(s.x,s.y);
 for(int i=0;i<3;i++){float fi=float(i);
  float b=floor((ang+3.14159265)/6.2831853*n);
  float h=h11(b*1.37+fi*11.3);
  float life=fract(t*speed*(.55+.9*h)+h*5.+fi*.37);
  float pa=((b+.5+(h11(b*3.1+fi)-.5)*.7)/n)*6.2831853-3.14159265;
  float bend=.35*life*sign(pa+.0001);
  float pr=1.05+pow(life,.8)*spread;
  vec2 pp=pr*vec2(sin(pa+bend*.3),cos(pa+bend*.3));
  float d=length(s-pp);float sz=.045+.04*h;
  float c=exp(-pow(pa/cone,2.));
  acc+=exp(-d*d/(sz*sz))*(1.-life)*sm(0.,.08,life)*c;
 }
 return acc;}
const float TILT=-0.29670597;const float INC=0.17;
vec3 coolColor(float rn,float dop){float t=clamp(rn-(dop-1.)*.35,0.,1.);return mix(vec3(1.,.985,.96),vec3(.42,.62,1.),pow(t,.8));}
float streaks(float th,float rho){float w=pow(rho/1.55,-1.5);float a=th+spin*w;vec2 e=vec2(cos(a),sin(a));
 float g=vn(e*9.+vec2(rho*7.,0.))*.6+vn(e*26.+vec2(0.,rho*19.))*.4;return .15+1.6*smoothstep(.38,.8,g);}
void main(){vec2 p=(qt_TexCoord0-0.5)*size;vec2 s=p/R;float r=length(s);float c=cos(TILT),sn=sin(TILT);
 vec2 q=vec2(s.x*c+s.y*sn,-s.x*sn+s.y*c);float bright=vis*(.5+.8*en);vec3 back=vec3(0.),front=vec3(0.);
 // resplandor frío amplio
 back+=vec3(.55,.7,1.)*vis*(.16+.12*en)*exp(-max(r-.9,0.)*.9)+vec3(.8,.88,1.)*vis*.08*exp(-max(r-.9,0.)*.3);
 // corrientes de EYECCIÓN: los grumos viajan hacia fuera, calientes (blancos) cerca y fríos lejos
 {float rr=length(q);float f=mix(1.,INC,sm(5.5,1.6,rr));float rho=length(vec2(q.x,q.y/f));f=mix(1.,INC,sm(5.5,1.6,rho));
  vec2 qd=vec2(q.x,q.y/f);rho=length(qd);
  if(rho>1.04&&rho<8.){float a=atan(qd.y,qd.x);float sarm=a-4.2*log(rho);const float N=12.;float arm=.5+.5*cos(N*sarm);
   float idx=mod(floor(N*sarm/6.2831853+.5),N);float m=pow(rho,1.4)/2.2-pull*1.3;float blob=smoothstep(.45,.88,vn(vec2(m*1.7,idx*7.31)));
   float heat=sm(5.5,1.4,rho);float al=vis*(.18+.6*en)*sm(8.,4.5,rho)*(.45+heat)*pow(arm,10.)*blob*1.2;
   back+=mix(vec3(.45,.62,1.),vec3(1.,.97,.93),heat)*al;}}
 // disco fino frío con Doppler (gira al revés que el negro)
 float yd=q.y/INC;float rho=length(vec2(q.x,yd));float th=atan(yd,q.x);
 if(rho>1.55&&rho<4.45){float rn=(rho-1.55)/2.9;float dop=1.+.8*cos(th)*pow(1.55/rho,.5);float edge=sm(1.55,1.75,rho)*(1.-sm(4.1,4.45,rho));
  float a=bright*pow(dop,2.)*(1.-rn*.5)*.5*streaks(th,rho)*edge;vec3 col=coolColor(rn,dop)*a;
  if(q.y<0.)back+=col;else{float ends=1.-smoothstep(.55,1.,abs(cos(th)));front+=col*(1.-rn*.6)*(.4+.9*smoothstep(-.2,1.,cos(th)))*(.5+.5*ends);}}
 // halo lensado sobre el núcleo
 {float qy=(-q.y-.02)/.92;if(qy>0.){float rh=length(vec2(q.x,qy));if(rh>1.12&&rh<2.07){float rn=(rh-1.12)/.95;
   float dop=1.+.8*(q.x/rh)*pow(1.55/(1.55+rn*2.9),.5);float edge=sm(1.12,1.2,rh)*(1.-sm(1.95,2.07,rh));
   back+=coolColor(rn,dop)*bright*pow(dop,2.)*(1.-rn*.5)*.35*streaks(atan(qy,q.x),1.55+rn*2.9)*edge;}}}
 // núcleo incandescente (donde el negro tiene la sombra): gradiente, granulado y limbo frío
 float body=vis*(1.-smoothstep(.88,1.06,r));
 float gran=fbm(s*3.2+vec2(tsec*.15,-tsec*.22));
 vec3 coreC=mix(vec3(1.,1.,1.),vec3(.72,.84,1.),sm(.3,1.,r))*(.82+.18*gran)*(1.+.25*en);
 // anillo de fotones y destellos
 {float lw=max(.7,(1.2+en)*U);float d=abs(r-1.05)*R;front+=vec3(.86,.93,1.)*vis*(.45+.6*en)*(1.-smoothstep(lw*.5,lw*.5+1.4,d));
  if(pulse>0.){float k=1.-pulse;float w1=2.4*U*pulse+.5;
   front+=vec3(.9,.95,1.)*pulse*(1.-smoothstep(w1*.5,w1*.5+1.6,abs(r-(1.08+k*6.))*R));
   front+=vec3(.6,.75,1.)*pulse*.6*(1.-smoothstep(w1*.5,w1*.5+1.6,abs(r-(1.08+k*3.6))*R));
   front+=vec3(1.)*pulse*pulse*exp(-r*r*.25)*.6;
   front+=vec3(.92,.96,1.)*sparks(s,tsec,40.,6.,.9,1.)*pulse*1.4;}}
 if(closing>0.)front+=vec3(1.)*closing*exp(-r*r*(1.6-closing))*.9;
 {float Rr=R*(1.45+.25*en)*vis;if(p.y>=0.&&Rr>1.){float dd=abs(length(p)-Rr);float amp=vis*(.35+.65*en);
  front+=vec3(.8,.88,1.)*amp*(.06*(1.-smoothstep(2.5*U,2.5*U+2.,dd))+.45*(1.-smoothstep(.7*U,.7*U+1.2,dd)));}}
 vec3 rgb=back*(1.-body)+coreC*body+front;rgb=1.-exp(-rgb*1.15);fragColor=vec4(rgb,body*.9)*qt_Opacity;}
