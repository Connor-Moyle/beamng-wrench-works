// SMAA Ultra colour edge detection with depth predication: where the depth is flat the threshold is doubled (texture detail is not an edge),
// where depth steps (a silhouette) it is lowered, so geometry edges are caught at Ultra sensitivity and fine texture noise is left alone.
#define SLRR_PREDICATED
#include "slrr_smaaUltra_edge.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
    float4 offset[3]  : TEXCOORD1;
};

float realDepthAt(float2 uv)
{
    return ndcToRealDepth(prepassDepthTex.SampleLevel(smaaPointSampler, uv, 0).r, projParams.zw);
}

float4 main(VertToPix IN) : SV_Target
{
    float d = realDepthAt(IN.uv0);
    float2 neighbours = float2(realDepthAt(IN.offset[0].xy), realDepthAt(IN.offset[0].zw));
    float2 rel = abs(d - neighbours) / max(d, 0.1);       // a step of more than 4 % of the distance is a silhouette
    float2 depthEdges = step(0.04, rel);
    slrrThreshold = 0.05 * 2.0 * (1.0 - 0.4 * max(depthEdges.x, depthEdges.y));
    return float4(SMAAColorEdgeDetectionPS(IN.uv0, IN.offset, colorTexGamma), 0, 0);
}
