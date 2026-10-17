// Wrench Works: graphics. Sharpening by AMD FidelityFX Contrast Adaptive Sharpening (CAS), after the anti-aliasing.
// The filter below follows AMD's reference algorithm (ffx_cas.h, non-scaling path). Its licence:
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
#ifndef SLRR_CAS_H_HLSL
#define SLRR_CAS_H_HLSL

#include "shaders/common/postFx/postFx.h.hlsl"

uniform_sampler2D(colorTex, 0);

cbuffer perDraw : register(b0)
{
    uniform float4 casParams;    // x, y: 1 / width, 1 / height of the picture; z: the sharpening 0..1

    POSTFX_UNIFORMS;
};

#include "shaders/common/postFx/postFx.hlsl"

#endif //SLRR_CAS_H_HLSL
