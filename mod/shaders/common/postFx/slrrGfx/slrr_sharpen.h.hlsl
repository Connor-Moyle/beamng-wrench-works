// Wrench Works: graphics. Shared header of the sharpening post effects that run after the anti-aliasing (FSR RCAS, NVIDIA NIS).
#ifndef SLRR_SHARPEN_H_HLSL
#define SLRR_SHARPEN_H_HLSL

#include "shaders/common/postFx/postFx.h.hlsl"

uniform_sampler2D(colorTex, 0);

cbuffer perDraw : register(b0)
{
    uniform float4 sharpParams;  // x, y: 1 / width, 1 / height of the picture; z: RCAS lobe scale (0..1)
    uniform float4 nisA;         // NIS: kSharpStartY, kSharpScaleY, kSharpStrengthMin, kSharpStrengthScale
    uniform float4 nisB;         // NIS: kSharpLimitMin, kSharpLimitScale, kRatioNorm, unused

    POSTFX_UNIFORMS;
};

#include "shaders/common/postFx/postFx.hlsl"

#endif //SLRR_SHARPEN_H_HLSL
