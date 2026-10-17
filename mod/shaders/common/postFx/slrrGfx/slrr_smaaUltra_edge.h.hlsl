// Wrench Works: graphics. Our own copy of the game's smaa_edgeDetection.h.hlsl with the SMAA Ultra preset (lower edge threshold) and colour edge detection.
// The game's own files are not touched: this folder sits next to shaders/common/postFx/smaa/ and includes the game's SMAA.h from there.
#ifndef SLRR_SMAA_ULTRA_EDGE_H_HLSL
#define SLRR_SMAA_ULTRA_EDGE_H_HLSL

#ifdef SLRR_PREDICATED
// depth predication: the threshold is worked out per pixel in the pixel shader (SMAA's own predication compares raw non-linear depth, which barely differs in the distance)
static float slrrThreshold = 0.05;
#define SMAA_THRESHOLD slrrThreshold
#else
#define SMAA_PRESET_ULTRA
#endif
#include "../postFx.h.hlsl"

Texture2D colorTexGamma : register(t0); // gamma space :(
Texture2D prepassDepthTex : register(t1); // only read when SLRR_PREDICATED
SamplerState smaaPointSampler : register(s0);
SamplerState smaaLinearSampler : register(s1);

cbuffer perDraw : register(b0)
{
    uniform float4 smaaRtMetrics;
    POSTFX_UNIFORMS
};

#include "../smaa/smaa_native.h.hlsl"
#define SMAA_RT_METRICS smaaRtMetrics
#include "../smaa/SMAA.h"
#include "../postFx.hlsl"

#endif //SLRR_SMAA_ULTRA_EDGE_H_HLSL
