#include "slrr_sharpen.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

// diagnosis only (G.probeShader(2)): the sharpeners' own vertex shader and header, painting everything magenta
float4 main(VertToPix IN) : SV_Target
{
    return float4(1.0, 0.0, 1.0, 1.0);
}
