// Wrench Works: graphics. Our own copy of the game's fxaa.h.hlsl: NVIDIA FXAA 3.11 at the top quality preset (39) with full sub-pixel removal.
// The game's Fxaa3_11.h is included from its own folder and not touched.
#ifndef SLRR_FXAA_HQ_H_HLSL
#define SLRR_FXAA_HQ_H_HLSL

#include "shaders/common/postFx/postFx.h.hlsl"

#define FXAA_PC 1
#define FXAA_HLSL_4 1
#define FXAA_QUALITY__PRESET 39
#define FXAA_GREEN_AS_LUMA 1

uniform_sampler2D(colorTex, 0);
#define FXAA_SAMPLER colorTex_sampler_

#include "../fxaa/Fxaa3_11.h"

cbuffer perDraw : register(b0)
{
    uniform float2 oneOverTargetSize;

    POSTFX_UNIFORMS;
};

#include "shaders/common/postFx/postFx.hlsl"

#endif //SLRR_FXAA_HQ_H_HLSL
