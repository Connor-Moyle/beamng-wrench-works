#include "slrr_smaaUltra_edge.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
    float4 offset[3]  : TEXCOORD1;
};

VertToPix main(PFXVert IN)
{
    VertToPix OUT;

    OUT.hpos = float4(IN.pos, 1.0f);
    OUT.uv0 = viewportCoordToRenderTarget(IN.uv, rtParams0);
    SMAAEdgeDetectionVS(OUT.uv0, OUT.offset);

    return OUT;
}
