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

    // mean and spread of the 3x3 colours around the pixel
    float3 cur = 0;
    float3 m1 = 0;
    float3 m2 = 0;
    for (int y = -1; y <= 1; ++y)
    {
        for (int x = -1; x <= 1; ++x)
        {
            float3 t = toT(curTexTex.Load(int3(clamp(px + int2(x, y), int2(0, 0), last), 0)).rgb);
            if (x == 0 && y == 0) cur = t;
            m1 += t;
            m2 += t * t;
        }
    }
    float3 mu = m1 / 9.0;
    float3 sigma = sqrt(max(m2 / 9.0 - mu * mu, 0.0));
    float3 lo = max(mu - 1.25 * sigma, 0.0);
    float3 hi = min(mu + 1.25 * sigma, 0.999);

    // where this pixel was last frame
    float2 vel = velTexTex.SampleLevel(velTex_sampler_, IN.uv0, 0).xy;
    float2 prevUv = IN.uv0 + vel;
    float4 hist = histTexTex.SampleLevel(histTex_sampler_, prevUv, 0);

    bool inside = all(prevUv >= 0.0) && all(prevUv <= 1.0);
    float valid = (hist.a > 0.5 && inside) ? 1.0 : 0.0;              // (the history starts out cleared: alpha 0)
    float velPx = length(vel * tsmSize.xy);
    float w = tsmParams.x * valid * saturate(1.0 - velPx * 0.08);     // fast movers: mostly the new picture

    float3 h = clamp(toT(hist.rgb), lo, hi);
    return float4(fromT(lerp(cur, h, w)), 1.0);
}
