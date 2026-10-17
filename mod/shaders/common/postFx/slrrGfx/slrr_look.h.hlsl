// Wrench Works: look. A light colour grade and vignette on the finished picture (after the anti-aliasing and the sharpening).
#ifndef SLRR_LOOK_H_HLSL
#define SLRR_LOOK_H_HLSL

#include "shaders/common/postFx/postFx.h.hlsl"

uniform_sampler2D(colorTex, 0);

cbuffer perDraw : register(b0)
{
    uniform float4 lookA;     // x: contrast (0..1); y: saturation (1 = as is); z: warmth (-1 cool .. 1 warm); w: colour split (0..1, teal shadows, warm highlights)
    uniform float4 lookB;     // x: vignette strength (0..1); y: width / height of the picture; z, w: unused

    POSTFX_UNIFORMS;
};

#include "shaders/common/postFx/postFx.hlsl"

#endif //SLRR_LOOK_H_HLSL
