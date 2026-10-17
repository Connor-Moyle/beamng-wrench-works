#include "slrr_cas.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

float3 casTap(float2 uv, float2 offset)
{
    return colorTexTex.SampleLevel(colorTex_sampler_, uv + offset * casParams.xy, 0).rgb;
}

float4 main(VertToPix IN) : SV_Target
{
    // a b c
    // d e f
    // g h i
    float3 a = casTap(IN.uv0, float2(-1, -1));
    float3 b = casTap(IN.uv0, float2( 0, -1));
    float3 c = casTap(IN.uv0, float2( 1, -1));
    float3 d = casTap(IN.uv0, float2(-1,  0));
    float4 eFull = colorTexTex.SampleLevel(colorTex_sampler_, IN.uv0, 0);
    float3 e = eFull.rgb;
    float3 f = casTap(IN.uv0, float2( 1,  0));
    float3 g = casTap(IN.uv0, float2(-1,  1));
    float3 h = casTap(IN.uv0, float2( 0,  1));
    float3 i = casTap(IN.uv0, float2( 1,  1));

    // Soft min and max: the cross, and the cross plus the corners (each 2.0x bigger: the extra multiply is factored out).
    float3 mn = min(min(min(d, e), min(f, b)), h);
    float3 mn2 = min(min(min(mn, a), min(c, g)), i);
    mn = mn + mn2;
    float3 mx = max(max(max(d, e), max(f, b)), h);
    float3 mx2 = max(max(max(mx, a), max(c, g)), i);
    mx = mx + mx2;

    // Smooth minimum distance to the signal limit, divided by the smooth max.
    float3 rcpM = rcp(mx);
    float3 amp = saturate(min(mn, 2.0 - mx) * rcpM);
    amp = sqrt(amp);

    // Filter shape: 0 w 0 / w 1 w / 0 w 0. The sharpening picks the peak between -1/8 (soft) and -1/5 (strong).
    float peak = -rcp(lerp(8.0, 5.0, saturate(casParams.z)));
    float3 w = amp * peak;
    float3 rcpWeight = rcp(1.0 + 4.0 * w);
    float3 outColor = saturate((b * w + d * w + f * w + h * w + e) * rcpWeight);

    return float4(outColor, eFull.a);
}
