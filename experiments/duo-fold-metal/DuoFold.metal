#include <metal_stdlib>
using namespace metal;

// Port of the mipmapped blur and edge shading in akashtdev/iphone-duo-animation,
// src/device/wipe.ts and src/device/foldable.ts (MIT, Copyright 2026 Akash T).
// The fold axis is rotated from the phone's vertical hinge to a MacBook's
// horizontal hinge. Source pixels remain in one texture through the effect.

struct FoldUniforms {
    float progress;
    float imageAnchor;
    float eyeDistance;
    float maxBlurLOD;
    float transitionWidth;
};

float w0(float a) { return (a * (a * (-a + 3.0) - 3.0) + 1.0) / 6.0; }
float w1(float a) { return (a * a * (3.0 * a - 6.0) + 4.0) / 6.0; }
float w2(float a) { return (a * (a * (-3.0 * a + 3.0) + 3.0) + 1.0) / 6.0; }
float w3(float a) { return a * a * a / 6.0; }

float4 bicubic(texture2d<float, access::sample> map, sampler sourceSampler,
               float2 uv, uint mipLevel) {
    float2 size = float2(map.get_width(mipLevel), map.get_height(mipLevel));
    float2 coordinate = uv * size + 0.5;
    float2 integerUV = floor(coordinate);
    float2 fractionUV = fract(coordinate);
    float gx0 = w0(fractionUV.x) + w1(fractionUV.x);
    float gx1 = w2(fractionUV.x) + w3(fractionUV.x);
    float gy0 = w0(fractionUV.y) + w1(fractionUV.y);
    float gy1 = w2(fractionUV.y) + w3(fractionUV.y);
    float hx0 = -1.0 + w1(fractionUV.x) / gx0;
    float hx1 = 1.0 + w3(fractionUV.x) / gx1;
    float hy0 = -1.0 + w1(fractionUV.y) / gy0;
    float hy1 = 1.0 + w3(fractionUV.y) / gy1;
    float2 p0 = (integerUV + float2(hx0, hy0) - 0.5) / size;
    float2 p1 = (integerUV + float2(hx1, hy0) - 0.5) / size;
    float2 p2 = (integerUV + float2(hx0, hy1) - 0.5) / size;
    float2 p3 = (integerUV + float2(hx1, hy1) - 0.5) / size;
    return gy0 * (gx0 * map.sample(sourceSampler, p0, level(float(mipLevel)))
                + gx1 * map.sample(sourceSampler, p1, level(float(mipLevel))))
         + gy1 * (gx0 * map.sample(sourceSampler, p2, level(float(mipLevel)))
                + gx1 * map.sample(sourceSampler, p3, level(float(mipLevel))));
}

float4 textureBicubic(texture2d<float, access::sample> map, sampler sourceSampler,
                      float2 uv, float lod) {
    uint lower = uint(floor(lod));
    uint upper = min(lower + 1, map.get_num_mip_levels() - 1);
    return mix(bicubic(map, sourceSampler, uv, lower),
               bicubic(map, sourceSampler, uv, upper), fract(lod));
}

kernel void renderDuoFold(texture2d<float, access::sample> source [[texture(0)]],
                          texture2d<float, access::write> output [[texture(1)]],
                          constant FoldUniforms& uniform [[buffer(0)]],
                          uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
    constexpr sampler sourceSampler(coord::normalized, address::clamp_to_edge,
                                    filter::linear, mip_filter::linear);
    float2 screen = (float2(pixel) + 0.5) /
                    float2(output.get_width(), output.get_height());
    float yFromHinge = 1.0 - screen.y;
    float foldAngle = clamp(uniform.progress, 0.0, 1.0) * 1.36135682;
    float sine = sin(foldAngle), cosine = cos(foldAngle);
    float eye = uniform.eyeDistance;
    float projectedTop = eye * cosine / (eye + sine);
    if (projectedTop <= 0.0) {
        output.write(float4(0.0, 0.0, 0.0, 1.0), pixel);
        return;
    }

    // Keep the top of the lid on the display while its internal projection
    // changes. Without this camera framing compensation most of the MacBook
    // display becomes empty black, unlike the reference's visible image.
    float projectedY = yFromHinge * projectedTop;
    float sourceY = eye * projectedY /
                    max(eye * cosine - projectedY * sine, 0.0001);
    float sourceX = 0.5 + (screen.x - 0.5) * (eye + sourceY * sine) / eye;
    float anchor = clamp(uniform.imageAnchor, 0.0, 1.0);
    float2 texturePlane = mix(float2(sourceX, sourceY),
                              float2(screen.x, yFromHinge), anchor);
    float2 textureUV = float2(texturePlane.x, 1.0 - texturePlane.y);

    // Reference wipe.ts: blur grows with distance from the hinge. The
    // horizontal-axis adaptation uses sourceY rather than the phone's x.
    float distanceToHinge = sourceY;
    float rampExponent = 1.2 / clamp(uniform.transitionWidth, 0.55, 1.8);
    float blurArea = clamp(uniform.progress *
                           (0.75 + 0.75 * pow(distanceToHinge, rampExponent)), 0.0, 1.5);
    float lod = min(blurArea * uniform.maxBlurLOD,
                    float(source.get_num_mip_levels() - 1));
    float3 colour = textureBicubic(source, sourceSampler, textureUV, lod).rgb;

    // Reference side shading, rotated to the MacBook's left/right edges.
    float sideDistance = abs(sourceX - 0.5) * 2.0;
    float sideShade = 1.0 - smoothstep(0.88, 1.0, sideDistance);
    float blurShade = 1.0 - 0.22 * smoothstep(0.85, 1.25, blurArea);
    float topShade = 1.0 - 0.45 * smoothstep(0.93, 1.0, sourceY);
    float validity = smoothstep(-0.02, 0.04, sourceX)
                   * (1.0 - smoothstep(0.96, 1.02, sourceX));
    colour *= sideShade * blurShade * topShade * validity;
    output.write(float4(colour, 1.0), pixel);
}
