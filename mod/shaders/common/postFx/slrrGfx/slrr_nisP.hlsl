// Wrench Works: graphics. Sharpening by NVIDIA Image Scaling, the NVSharpen path (NIS_SCALER 0, SDR, no upscaling), after the anti-aliasing.
// Ported from a compute shader with a shared-memory tile to a pixel shader that reads its own 5x5 luma support; the algorithm and its constants
// (NIS_Scaler.h, NIS_Config.h, NVSharpenUpdateConfig) are NVIDIA's. Their licence:
//
// The MIT License(MIT)
//
// Copyright(c) 2022 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files(the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and / or sell copies of
// the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#include "slrr_sharpen.h.hlsl"

struct VertToPix
{
    float4 hpos       : SV_Position;
    float2 uv0        : TEXCOORD0;
};

static const float kDetectRatio = 2.0 * 1127.0 / 1024.0;
static const float kDetectThres = 64.0 / 1024.0;
static const float kMinContrastRatio = 2.0;
static const float kContrastBoost = 1.0;
static const float kEps = 1.0 / 255.0;

float getY(float3 c)
{
    return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z;
}

float CalcLTIFast(float y[5])
{
    float a_min = min(min(y[0], y[1]), y[2]);
    float a_max = max(max(y[0], y[1]), y[2]);

    float b_min = min(min(y[2], y[3]), y[4]);
    float b_max = max(max(y[2], y[3]), y[4]);

    float a_cont = a_max - a_min;
    float b_cont = b_max - b_min;

    float cont_ratio = max(a_cont, b_cont) / (min(a_cont, b_cont) + kEps);
    return (1.0f - saturate((cont_ratio - kMinContrastRatio) * nisB.z)) * kContrastBoost;
}

float EvalUSM(float pxl[5], float sharpnessStrength, float sharpnessLimit)
{
    // USM profile
    float y_usm = -0.6001f * pxl[1] + 1.2002f * pxl[2] - 0.6001f * pxl[3];
    // boost USM profile
    y_usm *= sharpnessStrength;
    // clamp to the limit
    y_usm = min(sharpnessLimit, max(-sharpnessLimit, y_usm));
    // reduce ringing
    y_usm *= CalcLTIFast(pxl);

    return y_usm;
}

float4 GetDirUSM(float p[5][5])
{
    // sharpness boost & limit are the same for all directions
    float scaleY = 1.0f - saturate((p[2][2] - nisA.x) * nisA.y);
    // scale the ramp to sharpen as a function of luma
    float sharpnessStrength = scaleY * nisA.w + nisA.z;
    // scale the ramp to limit USM as a function of luma
    float sharpnessLimit = (scaleY * nisB.y + nisB.x) * p[2][2];

    float4 rval;
    // 0 deg filter
    float interp0Deg[5];
    for (int i = 0; i < 5; ++i) interp0Deg[i] = p[i][2];
    rval.x = EvalUSM(interp0Deg, sharpnessStrength, sharpnessLimit);

    // 90 deg filter
    float interp90Deg[5];
    for (int j = 0; j < 5; ++j) interp90Deg[j] = p[2][j];
    rval.y = EvalUSM(interp90Deg, sharpnessStrength, sharpnessLimit);

    // 45 deg filter
    float interp45Deg[5];
    interp45Deg[0] = p[1][1];
    interp45Deg[1] = lerp(p[2][1], p[1][2], 0.5f);
    interp45Deg[2] = p[2][2];
    interp45Deg[3] = lerp(p[3][2], p[2][3], 0.5f);
    interp45Deg[4] = p[3][3];
    rval.z = EvalUSM(interp45Deg, sharpnessStrength, sharpnessLimit);

    // 135 deg filter
    float interp135Deg[5];
    interp135Deg[0] = p[3][1];
    interp135Deg[1] = lerp(p[3][2], p[2][1], 0.5f);
    interp135Deg[2] = p[2][2];
    interp135Deg[3] = lerp(p[2][3], p[1][2], 0.5f);
    interp135Deg[4] = p[1][3];
    rval.w = EvalUSM(interp135Deg, sharpnessStrength, sharpnessLimit);
    return rval;
}

float4 GetEdgeMap(float p[5][5], int i, int j)
{
    float g_0 = abs(p[0 + i][0 + j] + p[0 + i][1 + j] + p[0 + i][2 + j] - p[2 + i][0 + j] - p[2 + i][1 + j] - p[2 + i][2 + j]);
    float g_45 = abs(p[1 + i][0 + j] + p[0 + i][0 + j] + p[0 + i][1 + j] - p[2 + i][1 + j] - p[2 + i][2 + j] - p[1 + i][2 + j]);
    float g_90 = abs(p[0 + i][0 + j] + p[1 + i][0 + j] + p[2 + i][0 + j] - p[0 + i][2 + j] - p[1 + i][2 + j] - p[2 + i][2 + j]);
    float g_135 = abs(p[1 + i][0 + j] + p[2 + i][0 + j] + p[2 + i][1 + j] - p[0 + i][1 + j] - p[0 + i][2 + j] - p[1 + i][2 + j]);

    float g_0_90_max = max(g_0, g_90);
    float g_0_90_min = min(g_0, g_90);
    float g_45_135_max = max(g_45, g_135);
    float g_45_135_min = min(g_45, g_135);

    float e_0_90 = 0;
    float e_45_135 = 0;

    if (g_0_90_max + g_45_135_max == 0)
    {
        return float4(0, 0, 0, 0);
    }

    e_0_90 = min(g_0_90_max / (g_0_90_max + g_45_135_max), 1.0f);
    e_45_135 = 1.0f - e_0_90;

    bool c_0_90 = (g_0_90_max > (g_0_90_min * kDetectRatio)) && (g_0_90_max > kDetectThres) && (g_0_90_max > g_45_135_min);
    bool c_45_135 = (g_45_135_max > (g_45_135_min * kDetectRatio)) && (g_45_135_max > kDetectThres) && (g_45_135_max > g_0_90_min);
    bool c_g_0_90 = g_0_90_max == g_0;
    bool c_g_45_135 = g_45_135_max == g_45;

    float f_e_0_90 = (c_0_90 && c_45_135) ? e_0_90 : 1.0f;
    float f_e_45_135 = (c_0_90 && c_45_135) ? e_45_135 : 1.0f;

    float weight_0 = (c_0_90 && c_g_0_90) ? f_e_0_90 : 0.0f;
    float weight_90 = (c_0_90 && !c_g_0_90) ? f_e_0_90 : 0.0f;
    float weight_45 = (c_45_135 && c_g_45_135) ? f_e_45_135 : 0.0f;
    float weight_135 = (c_45_135 && !c_g_45_135) ? f_e_45_135 : 0.0f;

    return float4(weight_0, weight_90, weight_45, weight_135);
}

float4 main(VertToPix IN) : SV_Target
{
    // the 5x5 luma support around this pixel; p[row][column]
    float p[5][5];
    for (int i = 0; i < 5; ++i)
    {
        for (int j = 0; j < 5; ++j)
        {
            float2 uv = IN.uv0 + float2(j - 2, i - 2) * sharpParams.xy;
            p[i][j] = getY(colorTexTex.SampleLevel(colorTex_sampler_, uv, 0).rgb);
        }
    }

    // directional filter bank output, weighted by the edge map
    float4 dirUSM = GetDirUSM(p);
    float4 w = GetEdgeMap(p, 1, 1);
    float usmY = dirUSM.x * w.x + dirUSM.y * w.y + dirUSM.z * w.z + dirUSM.w * w.w;

    float4 op = colorTexTex.SampleLevel(colorTex_sampler_, IN.uv0, 0);
    op.xyz += usmY;
    return float4(saturate(op.xyz), op.w);
}
