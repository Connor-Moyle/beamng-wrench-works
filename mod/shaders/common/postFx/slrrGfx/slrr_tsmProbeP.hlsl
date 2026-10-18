#include "slrr_tsm.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

// diagnosis only: paints the whole picture magenta, to tell whether the smoothing effect draws at all (G.probeShader())
float4 main(VertToPix IN) : SV_Target
{
    return float4(1.0, 0.0, 1.0, 1.0);
}
