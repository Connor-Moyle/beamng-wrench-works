#define SLRR_TSM_COPY
#include "slrr_tsm.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

// keeps the result of the smoothing for the next frame, with this pixel's depth in alpha (never 0: that marks an empty history)
float4 main(VertToPix IN) : SV_Target
{
    float depth = tsmRealDepth(depthTexTex.SampleLevel(depthTex_sampler_, IN.uv0, 0).r);
    return float4(curTexTex.SampleLevel(curTex_sampler_, IN.uv0, 0).rgb, depth);
}
