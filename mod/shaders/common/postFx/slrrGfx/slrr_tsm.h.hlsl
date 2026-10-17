// Wrench Works: graphics. Temporal smoothing: the finished (anti-aliased) picture is blended with last frame's, found through the game's own
// velocity buffer (#VelocityBuffer, last_uv - cur_uv, as the game's GTAO and motion blur read it), with the history clamped to the colours around the
// pixel so nothing ghosts. There is no camera jitter in the engine, so this does not add detail: it calms shimmer and crawling edges.
#ifndef SLRR_TSM_H_HLSL
#define SLRR_TSM_H_HLSL

#include "shaders/common/postFx/postFx.h.hlsl"

uniform_sampler2D(curTex, 0);     // the picture now ($backBuffer)
uniform_sampler2D(histTex, 1);    // last frame's result (#slrrTsmHist)
uniform_sampler2D(velTex, 2);     // #VelocityBuffer

cbuffer perDraw : register(b0)
{
    uniform float4 tsmParams;     // x: weight of the history (0..1)
    uniform float4 tsmSize;       // x, y: width and height of the picture in pixels

    POSTFX_UNIFORMS;
};

#include "shaders/common/postFx/postFx.hlsl"

#endif //SLRR_TSM_H_HLSL
