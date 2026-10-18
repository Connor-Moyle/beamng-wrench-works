// Wrench Works: graphics. Temporal smoothing: the finished (anti-aliased) picture is blended with last frame's, found through the game's own
// velocity buffer (#VelocityBuffer, last_uv - cur_uv, as the game's GTAO and motion blur read it), with the history clamped to the colours around the
// pixel so nothing ghosts. There is no camera jitter in the engine, so this does not add detail: it calms shimmer and crawling edges.
// The history keeps the picture's colour in rgb and the pixel's real depth in alpha (0 = nothing yet), so a history that shows a different surface
// (wind-animated leaves have no motion in the velocity buffer) can be told from one that shows the same.
// The same pass also calms specular sparkle (bright pixels on bumpy glossy surfaces, from the prepass normals and roughness), see slrr_tsmP.hlsl.
#ifndef SLRR_TSM_H_HLSL
#define SLRR_TSM_H_HLSL

#include "shaders/common/postFx/postFx.h.hlsl"

uniform_sampler2D(curTex, 0);     // the picture now ($backBuffer)
#ifdef SLRR_TSM_COPY
uniform_sampler2D(depthTex, 1);   // #prepass[Depth]
#else
uniform_sampler2D(histTex, 1);    // last frame's result (#slrrTsmHist)
uniform_sampler2D(velTex, 2);     // #VelocityBuffer
uniform_sampler2D(depthTex, 3);   // #prepass[Depth]
uniform_sampler2D(rt0Tex, 4);     // #prepass[RT0]: normal (octahedral) in xy, roughness in z
#endif

cbuffer perDraw : register(b0)
{
    uniform float4 tsmParams;     // x: weight of the history (0..1); y: how hard thin geometry (foliage, wires) cuts the history (0..1); z: colour clamp width; w: specular shimmer reduction (0..1)
    uniform float4 tsmSize;       // x, y: width and height of the picture in pixels; z: debug view (0 off, 1 risk, 2 normal spread, 3 glossiness, 4 sparkle)

    POSTFX_UNIFORMS;
};

#include "shaders/common/postFx/postFx.hlsl"

// real (view-space) depth in metres from the prepass depth, finite and positive
float tsmRealDepth(float ndc)
{
    float d = ndcToRealDepth(ndc, projParams.zw);
    if (!(d < 60000.0)) d = 60000.0;
    return max(d, 0.05);
}

#endif //SLRR_TSM_H_HLSL
