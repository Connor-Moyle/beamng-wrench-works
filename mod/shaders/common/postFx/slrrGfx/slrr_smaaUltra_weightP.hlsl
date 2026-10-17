#include "slrr_smaaUltra_weight.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
    float2 pixcoord   : TEXCOORD1;
    float4 offset[3]  : TEXCOORD2;
};

#define uSubsampleIndices 0 // required for temporal modes (SMAA T2x).

float4 main(VertToPix IN) : SV_Target
{
    return SMAABlendingWeightCalculationPS(IN.uv0, IN.pixcoord, IN.offset, edgesTex, areaTex, searchTex, uSubsampleIndices);
}
