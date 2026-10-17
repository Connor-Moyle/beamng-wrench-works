// Wrench Works: graphics. Our own copy of the game's smaa_edgeDetection.h.hlsl with the SMAA Ultra preset (lower edge threshold) and colour edge detection.
// The game's own files are not touched: this folder sits next to shaders/common/postFx/smaa/ and includes the game's SMAA.h from there.
#ifndef SLRR_SMAA_ULTRA_EDGE_H_HLSL
#define SLRR_SMAA_ULTRA_EDGE_H_HLSL

#define SMAA_PRESET_ULTRA
#include "../postFx.h.hlsl"

Texture2D colorTexGamma : register(t0); // gamma space :(
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
