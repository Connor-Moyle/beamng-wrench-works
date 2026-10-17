// Wrench Works: graphics. Sharpening by AMD FidelityFX Super Resolution 1.0 RCAS (Robust Contrast Adaptive Sharpening), after the anti-aliasing,
// at the picture's own size (no upscaling). The filter follows AMD's reference algorithm (ffx_fsr1.h, FsrRcasF). Its licence:
//
// Copyright (c) 2019-2021 Advanced Micro Devices, Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
#include "slrr_sharpen.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

#define FSR_RCAS_LIMIT (0.25 - (1.0 / 16.0))

float3 rcasTap(float2 uv, float2 offset)
{
    return colorTexTex.SampleLevel(colorTex_sampler_, uv + offset * sharpParams.xy, 0).rgb;
}

float4 main(VertToPix IN) : SV_Target
{
    //   b
    // d e f
    //   h
    float3 b = rcasTap(IN.uv0, float2( 0, -1));
    float3 d = rcasTap(IN.uv0, float2(-1,  0));
    float4 eFull = colorTexTex.SampleLevel(colorTex_sampler_, IN.uv0, 0);
    float3 e = eFull.rgb;
    float3 f = rcasTap(IN.uv0, float2( 1,  0));
    float3 h = rcasTap(IN.uv0, float2( 0,  1));

    // Min and max of the ring.
    float3 mn4 = min(min(min(b, d), f), h);
    float3 mx4 = max(max(max(b, d), f), h);

    // Limiters: how far the lobe can go before the result clips (the divisions are guarded against black and white rings).
    float3 hitMin = min(mn4, e) * rcp(4.0 * max(mx4, 1e-4));
    float3 hitMax = (1.0 - max(mx4, e)) * rcp(4.0 * mn4 - 4.0 - 1e-4);
    float3 lobe3 = max(-hitMin, hitMax);
    float lobe = max(-FSR_RCAS_LIMIT, min(max(max(lobe3.r, lobe3.g), lobe3.b), 0.0)) * sharpParams.z;

    float rcpL = rcp(4.0 * lobe + 1.0);
    float3 outColor = saturate((lobe * b + lobe * d + lobe * h + lobe * f + e) * rcpL);

    return float4(outColor, eFull.a);
}
