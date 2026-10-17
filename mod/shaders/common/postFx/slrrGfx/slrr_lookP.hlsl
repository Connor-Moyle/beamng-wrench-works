#include "slrr_look.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

float luma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

// a cheap hash of the pixel position, 0..1
float hash12(float2 p)
{
    float3 p3 = frac(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float4 main(VertToPix IN) : SV_Target
{
    float3 c = saturate(colorTexTex.SampleLevel(colorTex_sampler_, IN.uv0, 0).rgb);

    // split toning: cool shadows, warm highlights (small, so it stays a tint)
    float l = luma(c);
    c += lookA.w * ((1.0 - l) * (1.0 - l) * float3(-0.020, 0.008, 0.028) + l * l * float3(0.030, 0.012, -0.030));

    // warm / cool
    c *= float3(1.0 + 0.06 * lookA.z, 1.0 + 0.01 * lookA.z, 1.0 - 0.06 * lookA.z);
    c = saturate(c);

    // filmic contrast: the S-curve (smoothstep) blended in
    c = lerp(c, c * c * (3.0 - 2.0 * c), lookA.x);

    // saturation about the picture's own luma
    c = saturate(lerp(luma(c).xxx, c, lookA.y));

    // vignette: round on screen (aspect-corrected), starting outside the middle, smooth
    float2 p = (IN.uv0 - 0.5) * float2(lookB.y, 1.0);
    float d = length(p) / length(float2(0.5 * lookB.y, 0.5));
    c *= 1.0 - lookB.x * smoothstep(0.35, 1.05, d);

    // one step of dither (triangular) so the 8-bit picture does not band
    float n = hash12(IN.hpos.xy) + hash12(IN.hpos.xy + 17.0) - 1.0;
    c += n / 255.0;

    return float4(saturate(c), 1.0);
}
