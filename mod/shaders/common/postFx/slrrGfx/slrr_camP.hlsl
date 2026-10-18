#include "slrr_cam.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

float4 main(VertToPix IN) : SV_Target
{
    float3 c = colorTexTex.SampleLevel(colorTex_sampler_, IN.uv0, 0).rgb;

    // distance of this row from the nearest picture edge, against the bar height; one pixel of soft edge
    float edge = min(IN.uv0.y, 1.0 - IN.uv0.y);
    c *= saturate((edge - camA.x) / camA.y + 0.5);

    return float4(c, 1.0);
}
