#include "slrr_tsm.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

// keeps the result of the smoothing for the next frame; alpha 1 marks the history as filled
float4 main(VertToPix IN) : SV_Target
{
    return float4(curTexTex.SampleLevel(curTex_sampler_, IN.uv0, 0).rgb, 1.0);
}
