#include "slrr_fxaaHQ.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

// The game's own call (fxaa/fxaaP.hlsl) with the sub-pixel removal raised from 0.90 to the upper limit 1.00; the rest is the same.
float4 main(VertToPix IN) : SV_Target
{
    return FxaaPixelShader(
        IN.uv0, 0,
        colorTexTex, colorTexTex, colorTexTex,
        oneOverTargetSize,
        0, 0, 0,
        1.00,   // sub-pixel aliasing removal (softer, kills shimmer on thin lines)
        0.063,  // edge threshold: "overkill" quality
        0,      // darks threshold: process everything
        8, 0, 0, 0);
}
