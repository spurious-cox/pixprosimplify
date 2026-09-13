#!/usr/bin/env python3
"""Controllable anchor-point reducer for an SVG cubic-bezier path.
RDP on the anchor points (keeps original in/out control handles at kept anchors),
so I can dial the reduction to any level, unlike Inkscape's fixed path-simplify.
Usage: reduce.py in.svg out.svg <epsilon>   (bigger epsilon = fewer points)
v1.0 2026-07-15"""
import sys, re, math

def tokenize(d):
    # returns list of (cmd, [floats])
    toks = re.findall(r'([MmLlHhVvCcSsQqTtAaZz])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)', d)
    out=[]; nums=[]; cmd=None
    def flush():
        if cmd is not None: out.append((cmd, nums[:]))
    for c,n in toks:
        if c:
            flush(); nums=[]; cmd=c
        else:
            nums.append(float(n))
    flush()
    return out

def parse_subpaths(d):
    """Return list of subpaths; each = list of anchors {p, out, in_} (absolute)."""
    subs=[]; cur=None; pos=(0,0); start=(0,0)
    toks=tokenize(d)
    i=0
    for cmd,nums in toks:
        C=cmd.upper(); rel=cmd.islower()
        def A(x,y):
            return (pos[0]+x, pos[1]+y) if rel else (x,y)
        if C=='M':
            # first pair is moveto, extras are implicit L
            k=0
            x,y=nums[0],nums[1]; p=A(x,y); pos=p; start=p
            cur=[{'p':p,'out':p,'in':p}]; subs.append(cur)
            k=2
            while k+1<len(nums):
                x,y=nums[k],nums[k+1]; p=A(x,y)
                cur[-1]['out']=cur[-1]['p']; cur.append({'p':p,'out':p,'in':cur[-1]['p'] if False else p})
                pos=p; k+=2
        elif C=='L':
            k=0
            while k+1<len(nums):
                x,y=nums[k],nums[k+1]; p=A(x,y)
                cur[-1]['out']=cur[-1]['p']
                cur.append({'p':p,'out':p,'in':p})
                pos=p; k+=2
        elif C=='H':
            for x in nums:
                p=(pos[0]+x,pos[1]) if rel else (x,pos[1])
                cur[-1]['out']=cur[-1]['p']; cur.append({'p':p,'out':p,'in':p}); pos=p
        elif C=='V':
            for y in nums:
                p=(pos[0],pos[1]+y) if rel else (pos[0],y)
                cur[-1]['out']=cur[-1]['p']; cur.append({'p':p,'out':p,'in':p}); pos=p
        elif C=='C':
            k=0
            while k+5<len(nums):
                c1=A(nums[k],nums[k+1]); c2=A(nums[k+2],nums[k+3]); p=A(nums[k+4],nums[k+5])
                cur[-1]['out']=c1
                cur.append({'p':p,'out':p,'in':c2})
                pos=p; k+=6
        elif C=='Z':
            if cur: cur.append({'p':start,'out':start,'in':start,'close':True}); pos=start
        # (S/Q/T/A rare in Pixelmator export; ignored/approximated as needed)
    return subs

def rdp(pts, eps):
    if len(pts)<3: return list(range(len(pts)))
    keep=[False]*len(pts); keep[0]=keep[-1]=True
    stack=[(0,len(pts)-1)]
    while stack:
        a,b=stack.pop()
        if b<=a+1: continue
        (x1,y1),(x2,y2)=pts[a],pts[b]
        dx,dy=x2-x1,y2-y1; L=math.hypot(dx,dy) or 1e-9
        dmax=0; idx=-1
        for i in range(a+1,b):
            x0,y0=pts[i]
            dist=abs(dy*x0-dx*y0+x2*y1-y2*x1)/L
            if dist>dmax: dmax=dist; idx=i
        if dmax>eps:
            keep[idx]=True; stack.append((a,idx)); stack.append((idx,b))
    return [i for i,k in enumerate(keep) if k]

def rdp_any(pts, eps):
    """RDP that also handles closed loops (start==end) by splitting at the
    farthest point from the start first."""
    if len(pts) < 3:
        return list(range(len(pts)))
    if pts[0] == pts[-1]:
        x0, y0 = pts[0]
        far = max(range(1, len(pts)-1),
                  key=lambda i: (pts[i][0]-x0)**2 + (pts[i][1]-y0)**2)
        a = rdp(pts[:far+1], eps)
        b = rdp(pts[far:], eps)
        return sorted(set(a) | set(i+far for i in b))
    return rdp(pts, eps)

def fnum(v): return f'{v:.2f}'.rstrip('0').rstrip('.')

def rebuild(subs, eps):
    parts=[]
    for anchors in subs:
        closed = anchors[-1].get('close')
        pts=[a['p'] for a in anchors]
        kept=rdp_any(pts, eps)
        ks=[anchors[i] for i in kept]
        if len(ks)<2:
            ks=anchors
        d=f"M{fnum(ks[0]['p'][0])},{fnum(ks[0]['p'][1])}"
        for a,b in zip(ks,ks[1:]):
            d+=(f"C{fnum(a['out'][0])},{fnum(a['out'][1])} "
                f"{fnum(b['in'][0])},{fnum(b['in'][1])} "
                f"{fnum(b['p'][0])},{fnum(b['p'][1])}")
        if closed: d+="Z"
        parts.append(d)
    return " ".join(parts)

def main():
    inp,out,eps=sys.argv[1],sys.argv[2],float(sys.argv[3])
    s=open(inp).read()
    def repl(m):
        d=m.group(1)
        subs=parse_subpaths(d)
        return m.group(0).replace(d, rebuild(subs,eps))
    s2=re.sub(r'<path[^>]*\sd="([^"]*)"', repl, s, count=0)
    open(out,'w').write(s2)
    # count
    cmds=sum(len(re.findall(r'[MmLlHhVvCcSsQqTtAaZz]',d)) for d in re.findall(r'<path[^>]*\sd="([^"]*)"', s2))
    print(f"eps={eps} -> {cmds} commands")

if __name__=='__main__': main()
