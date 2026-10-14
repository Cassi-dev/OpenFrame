"""Ajusta os modelos dos filtros fotográficos e gera o FilterModels.cpp.

Ajuste (precisa de numpy; a grade densa vem de gerar-efeitos.sh com "denso"):
    ajustar-filtros.py <denso.json> mono,noir,... <modelos.json>
Geração do C++ (só a biblioteca padrão):
    ajustar-filtros.py --cpp <modelos.json> <FilterModels.cpp>
Rodar a partir da raiz do repositório.
"""
import json, sys

ORDEM = ['mono', 'noir', 'tonal', 'chrome', 'fade', 'instant', 'process', 'transfer', 'sepia']

def cfloat(x):
    s = '%g' % x
    if '.' not in s and 'e' not in s and 'n' not in s:
        s += '.'
    return s + 'f'

def gerar_cpp(modelos_path, saida):
    modelos = json.load(open(modelos_path))
    linhas = ['// Gerado por qt/tests/tools/ajustar-filtros.py a partir das medições do Core Image',
              '// (qt/tests/tools/efeitos). Não editar à mão.',
              '#include "FilterModels.h"', '', 'namespace of::filtermodels {', '']
    for nome in ORDEM:
        m = modelos[nome]
        linhas.append('// %s: média %.2f, máximo %.0f níveis na grade 9×9×9' % (nome, m['mean'], m['max']))
        linhas.append('const Model %s = {' % nome)
        linhas.append('    %s, %d,' % ('true' if m['space'] == 'lin' else 'false', m['order']))
        mat = [list(row) + [0.0] * (10 - len(row)) for row in m['M']]
        linhas.append('    {%s},' % ', '.join('{%s}' % ', '.join(map(cfloat, row)) for row in mat))
        linhas.append('    {%s},' % ', '.join('{%s}' % ', '.join(map(cfloat, c)) for c in m['curves']))
        linhas.append('};')
        linhas.append('')
    linhas.append('} // namespace of::filtermodels')
    open(saida, 'w').write('\n'.join(linhas) + '\n')

if len(sys.argv) > 1 and sys.argv[1] == '--cpp':
    gerar_cpp(sys.argv[2], sys.argv[3])
    sys.exit(0)

import numpy as np
def lin(v): v=np.asarray(v,float); return np.where(v<=0.04045, v/12.92, ((np.maximum(v,0)+0.055)/1.055)**2.4)
def enc(v): v=np.clip(v,0,1); return np.where(v<=0.0031308, v*12.92, 1.055*v**(1/2.4)-0.055)
Dd=json.load(open(sys.argv[1])); Cd=np.array(Dd['colors'],float)/255
cd={c['name']:np.array(c['output'],float) for c in Dd['cases']}
Ds=json.load(open('qt/tests/fixtures/efeitos.json')); Cs=np.array(Ds['colors'],float)/255
cs={c['name']:np.array(c['output'],float) for c in Ds['cases']}
K=17; knots=np.linspace(0,1,K)
def basis(y):
    y=np.clip(y,0,1)*(K-1); i=np.minimum(np.floor(y).astype(int),K-2); f=y-i
    B=np.zeros((len(y),K)); B[np.arange(len(y)),i]=1-f; B[np.arange(len(y)),i+1]+=f; return B
def feats(x, space, order):
    if space=='lin': x=lin(x)
    r,g,b=x[:,0],x[:,1],x[:,2]; F=[r,g,b,np.ones_like(r)]
    if order>=2: F+=[r*r,g*g,b*b,r*g,r*b,g*b]
    return np.stack(F,1)
D2=np.diff(np.eye(K),2,axis=0)
def fitcurve(y,t,lam=1e-3):
    B=basis(y); A=np.vstack([B, np.sqrt(lam)*D2]); v,*_=np.linalg.lstsq(A,np.concatenate([t,np.zeros(K-2)]),rcond=None)
    return np.maximum.accumulate(v) if v[-1]>=v[0] else np.minimum.accumulate(v)
def invcurve(v,t):
    # inverte a curva monótona (por interpolação)
    if v[-1]<v[0]: return np.interp(t, v[::-1], knots[::-1])
    return np.interp(t, v, knots)
def run(name, space, order, iters=40):
    G=cd[f'filter.{name}=1.0']/255; F=feats(Cd,space,order)
    vals=np.tile(knots,(3,1)); M=np.zeros((3,F.shape[1]))
    for it in range(iters):
        for c in range(3):
            target=invcurve(vals[c],G[:,c])
            M[c],*_=np.linalg.lstsq(F,target,rcond=None)
            y=enc(F@M[c]) if False else F@M[c]
            vals[c]=fitcurve(y,G[:,c])
    def pred(C):
        F=feats(C,space,order); return np.stack([basis(F@M[c])@vals[c] for c in range(3)],1)
    ed=np.abs(np.round(np.clip(pred(Cd),0,1)*255)-cd[f'filter.{name}=1.0'])
    es=np.abs(np.round(np.clip(pred(Cs),0,1)*255)-cs[f'filter.{name}=1.0'])
    return M,vals,ed,es
res={}
for name in sys.argv[2].split(','):
    best=None
    for space in ['srgb','lin']:
        for order in [1,2]:
            M,vals,ed,es=run(name,space,order)
            print(name,space,order,'denso max %.0f média %.2f p95 %.0f | fixture max %.0f média %.2f'%(ed.max(),ed.mean(),np.percentile(ed,95),es.max(),es.mean()),flush=True)
            score=ed.mean()+0.02*ed.max()+(0 if order==1 else 0.3)
            if best is None or score<best['score']: best={'score':score,'space':space,'order':order,'M':M.tolist(),'curves':vals.tolist(),'max':float(ed.max()),'mean':float(ed.mean())}
    res[name]=best
json.dump(res,open(sys.argv[3],'w'))
