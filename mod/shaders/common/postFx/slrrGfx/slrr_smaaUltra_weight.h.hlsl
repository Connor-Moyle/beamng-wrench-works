// Wrench Works: graphics. Our own copy of the game's smaa_blendingWeight.h.hlsl with the SMAA Ultra preset (32 search steps, 16 diagonal, corner rounding).
#ifndef SLRR_SMAA_ULTRA_WEIGHT_H_HLSL
#define SLRR_SMAA_ULTRA_WEIGHT_H_HLSL

#define SMAA_PRESET_ULTRA
#include "../postFx.h.hlsl"
#include "shaders/common/bng.hlsl"

Texture2D edgesTex : register(t0);
Texture2D areaTex : register(t1);
Texture2D searchTex : register(t2);
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

#endif //SLRR_SMAA_ULTRA_WEIGHT_H_HLSL
