#include "slrr_tsm.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

// a reversible squash of any brightness into 0..1, so the clamp below works the same for bright highlights
float3 toT(float3 c)
{
    return c / (1.0 + max(c.r, max(c.g, c.b)));
}

float3 fromT(float3 t)
{
    return t / (1.0 - min(max(t.r, max(t.g, t.b)), 0.999));
}

float lumaT(float3 t)
{
    return dot(t, float3(0.2126, 0.7152, 0.0722));
}

float4 main(VertToPix IN) : SV_Target
{
    int2 px = int2(IN.hpos.xy);
    float dbg = tsmSize.z;
#ifdef SLRR_FORCE_DEBUG
    dbg = SLRR_FORCE_DEBUG;       // diagnosis build (slrr_tsmForceP.hlsl): the debug view without the constant
#endif
    int2 last = int2(tsmSize.xy) - 1;

    // the centre pixel first: its colour, depth, normal and roughness
    float3 cur = toT(curTexTex.Load(int3(px, 0)).rgb);
    float dCur = tsmRealDepth(depthTexTex.Load(int3(px, 0)).r);
    float4 g0 = rt0TexTex.Load(int3(px, 0));
    float3 nCur = decodeNormalOct(g0.xy);
    float rough = saturate(g0.z);

    // mean and spread of the 3x3 colours around the pixel, the range of their depths, how far their normals turn away, and the mean of those on the same surface
    float3 m1 = 0;
    float3 m2 = 0;
    float3 sameSum = 0;
    float sameCount = 0;
    float dMin = 1e9;
    float dMax = 0;
    float minDot = 1.0;
    for (int y = -1; y <= 1; ++y)
    {
        for (int x = -1; x <= 1; ++x)
        {
            int2 p = clamp(px + int2(x, y), int2(0, 0), last);
            float3 t = toT(curTexTex.Load(int3(p, 0)).rgb);
            float d = tsmRealDepth(depthTexTex.Load(int3(p, 0)).r);
            float3 n = decodeNormalOct(rt0TexTex.Load(int3(p, 0)).xy);
            float nDot = dot(n, nCur);
            m1 += t;
            m2 += t * t;
            dMin = min(dMin, d);
            dMax = max(dMax, d);
            minDot = min(minDot, nDot);
            if (abs(d - dCur) < 0.03 * dCur && nDot > 0.9)
            {
                sameSum += t;
                sameCount += 1.0;
            }
        }
    }
    float3 mu = m1 / 9.0;
    float3 sigma = sqrt(max(m2 / 9.0 - mu * mu, 0.0));
    float3 lo = max(mu - tsmParams.z * sigma, 0.0);
    float3 hi = min(mu + tsmParams.z * sigma, 0.999);

    // thin geometry (leaves, fences, wires): many depth steps around the pixel, and the velocity cannot be trusted on wind-animated vertices
    float thin = saturate(((dMax - dMin) / max(dCur, 0.1) - 0.02) / 0.08);

    // specular sparkle: a bright pixel (against its surroundings) on a glossy surface whose normals vary (bumpy paint, rain-wet road), away from silhouettes
    float normalSpread = saturate((1.0 - minDot) * 4.0);
    float gloss = saturate(1.0 - rough * 1.2);
    float sparkle = saturate((lumaT(cur) - lumaT(mu)) * 4.0);
    float risk = normalSpread * gloss * sparkle * (1.0 - thin);
    float spec = tsmParams.w;

    if (dbg > 4.5)      // probes: 5 solid magenta (the pass runs), 6 prepass RT0.z, 7 RT0.w, 8 RT0.x (grey)
    {
        float v = dbg < 5.5 ? 0.0 : (dbg < 6.5 ? g0.z : (dbg < 7.5 ? g0.w : g0.x));
        return dbg < 5.5 ? float4(1, 0, 1, 1) : float4(v, v, v, 1.0);
    }
    if (dbg > 0.5)      // debug views: the mask and what it is made of, as grey
    {
        float v =dbg < 1.5 ? risk : (dbg < 2.5 ? normalSpread : (dbg < 3.5 ? gloss : sparkle));
        return float4(v, v, v, 1.0);
    }

    // where this pixel was last frame
    float2 vel = velTexTex.SampleLevel(velTex_sampler_, IN.uv0, 0).xy;
    float2 prevUv = IN.uv0 + vel;
    float4 hist = histTexTex.SampleLevel(histTex_sampler_, prevUv, 0);

    bool inside = all(prevUv >= 0.0) && all(prevUv <= 1.0);
    float valid = (hist.a > 0.0 && inside) ? 1.0 : 0.0;              // (the history starts out cleared: alpha 0)
    float velPx = length(vel * tsmSize.xy);
    float velFactor = saturate(1.0 - velPx * 0.08);                   // fast movers: mostly the new picture
    // the history shows a clearly different distance than this pixel (allowing for the camera's own motion): another surface
    float mismatch = abs(dCur - hist.a) / max(dCur, 0.1);
    float sameSurface = 1.0 - smoothstep(0.15, 0.4, mismatch);

    float3 hRaw = toT(hist.rgb);
    float3 h = clamp(hRaw, lo, hi);
    float colourTrust = 1.0 - saturate(length(hRaw - h) * 6.0);      // the clamp had to change the history a lot: do not trust it

    float trust = valid * velFactor * sameSurface * colourTrust;
    float w = tsmParams.x * trust * (1.0 - thin * tsmParams.y);

    // sparkle on a glossy surface: cut the pixel's brightness to what the history had (plus a margin) and lean harder on the history
    float riskSpec = risk * spec;
    if (valid > 0.5 && riskSpec > 0.0)
    {
        float allowed = lumaT(h) + 0.10 + 0.4 * (1.0 - riskSpec);
        float curL = lumaT(cur);
        if (curL > allowed) cur *= allowed / curL;
        w = lerp(w, max(w, 0.95 * trust), riskSpec);
    }

    float3 outT = lerp(cur, h, w);

    // and a highlight-only blur: the sparkle pixel moves towards the mean of the pixels on its own surface (works with the history off too)
    if (riskSpec > 0.0 && sameCount > 1.5)
    {
        float3 same = sameSum / sameCount;
        outT = lerp(outT, same, 0.6 * riskSpec);
    }

    return float4(fromT(outT), 1.0);
}
