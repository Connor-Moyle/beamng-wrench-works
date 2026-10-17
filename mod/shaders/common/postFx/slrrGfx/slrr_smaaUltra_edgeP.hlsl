#include "slrr_smaaUltra_edge.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
    float4 offset[3]  : TEXCOORD1;
};

float4 main(VertToPix IN) : SV_Target
{
    // colour edge detection (the game's own copy detects on luma only)
    return float4(SMAAColorEdgeDetectionPS(IN.uv0, IN.offset, colorTexGamma), 0, 0);
}
