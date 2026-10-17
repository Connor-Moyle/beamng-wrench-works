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

float4 main(VertToPix IN) : SV_Target
{
    int2 px = int2(IN.hpos.xy);
    int2 last = int2(tsmSize.xy) - 1;

    // mean and spread of the 3x3 colours around the pixel, and the range of their depths
    float3 cur = 0;
    float3 m1 = 0;
    float3 m2 = 0;
    float dMin = 1e9;
    float dMax = 0;
    float dCur = 0;
    for (int y = -1; y <= 1; ++y)
    {
        for (int x = -1; x <= 1; ++x)
        {
            int2 p = clamp(px + int2(x, y), int2(0, 0), last);
            float3 t = toT(curTexTex.Load(int3(p, 0)).rgb);
            float d = tsmRealDepth(depthTexTex.Load(int3(p, 0)).r);
            if (x == 0 && y == 0) { cur = t; dCur = d; }
            m1 += t;
            m2 += t * t;
            dMin = min(dMin, d);
            dMax = max(dMax, d);
        }
    }
    float3 mu = m1 / 9.0;
    float3 sigma = sqrt(max(m2 / 9.0 - mu * mu, 0.0));
    float3 lo = max(mu - tsmParams.z * sigma, 0.0);
    float3 hi = min(mu + tsmParams.z * sigma, 0.999);

    // where this pixel was last frame
    float2 vel = velTexTex.SampleLevel(velTex_sampler_, IN.uv0, 0).xy;
    float2 prevUv = IN.uv0 + vel;
    float4 hist = histTexTex.SampleLevel(histTex_sampler_, prevUv, 0);

    bool inside = all(prevUv >= 0.0) && all(prevUv <= 1.0);
    float valid = (hist.a > 0.0 && inside) ? 1.0 : 0.0;              // (the history starts out cleared: alpha 0)
    float velPx = length(vel * tsmSize.xy);
    float w = tsmParams.x * valid * saturate(1.0 - velPx * 0.08);     // fast movers: mostly the new picture

    // thin geometry (leaves, fences, wires): many depth steps around the pixel, and the velocity cannot be trusted on wind-animated vertices
    float thin = saturate(((dMax - dMin) / max(dCur, 0.1) - 0.02) / 0.08);
    w *= 1.0 - thin * tsmParams.y;
    // the history shows a clearly different distance than this pixel (allowing for the camera's own motion): another surface
    float mismatch = abs(dCur - hist.a) / max(dCur, 0.1);
    w *= 1.0 - smoothstep(0.15, 0.4, mismatch);

    float3 hRaw = toT(hist.rgb);
    float3 h = clamp(hRaw, lo, hi);
    w *= 1.0 - saturate(length(hRaw - h) * 6.0);                      // the clamp had to change the history a lot: do not trust it

    return float4(fromT(lerp(cur, h, w)), 1.0);
}
