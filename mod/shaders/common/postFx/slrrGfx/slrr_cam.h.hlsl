// Wrench Works: cinematic camera. Letterbox bars on the finished picture (after the grade).
#ifndef SLRR_CAM_H_HLSL
#define SLRR_CAM_H_HLSL

#include "shaders/common/postFx/postFx.h.hlsl"

uniform_sampler2D(colorTex, 0);

cbuffer perDraw : register(b0)
{
    uniform float4 camA;      // x: height of each bar as a fraction of the picture height (0 = no bars); y: 1 / picture height in pixels; z, w: unused

    POSTFX_UNIFORMS;
};

#include "shaders/common/postFx/postFx.hlsl"

#endif //SLRR_CAM_H_HLSL
