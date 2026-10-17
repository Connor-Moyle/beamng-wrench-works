#include "slrr_cam.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

float4 main(VertToPix IN) : SV_Target
{
    float3 c = colorTexTex.SampleLevel(colorTex_sampler_, IN.uv0, 0).rgb;

    // distance from the nearest picture edge against the bar size (top / bottom, left / right); one pixel of soft edge
    float edgeY = min(IN.uv0.y, 1.0 - IN.uv0.y);
    float edgeX = min(IN.uv0.x, 1.0 - IN.uv0.x);
    c *= saturate((edgeY - camA.x) / camA.y + 0.5) * saturate((edgeX - camA.z) / camA.w + 0.5);

    return float4(c, 1.0);
}
