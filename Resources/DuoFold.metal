#include <metal_stdlib>
using namespace metal;

// Port of the mipmapped blur and edge shading in akashtdev/iphone-duo-animation,
// src/device/wipe.ts and src/device/foldable.ts (MIT, Copyright 2026 Akash T).
// The fold axis is rotated from the phone's vertical hinge to a MacBook's
// horizontal hinge. Source pixels remain in one texture through the effect.

struct FoldUniforms {
    float progress;
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
    // Inverse of the September 22 foldVertex projection. The hinge stays at
    // the bottom of the display; the upper edge recedes as the lid closes.
    // Reframing the projected top to fill the viewport made the image appear
    // to fly away instead of folding with the physical screen.
    float sourceY = eye * yFromHinge /
                    max(eye * cosine + sine * (0.5 - yFromHinge), 0.0001);
    float projection = eye / (eye + sourceY * sine);
    float sourceX = 0.5 + (screen.x - 0.5) / projection;
    float foldProgress = clamp(uniform.progress, 0.0, 1.0);
    float fromHinge = clamp(sourceY, 0.0, 1.0);
    float featherScale = clamp(uniform.transitionWidth, 0.55, 1.8);
    // The hinge edge remains almost crisp. The same side boundary gets softer
    // toward the free edge, where the glass is farther from the image plane.
    float sideWidth = (0.004 + foldProgress *
                       (0.006 + 0.14 * pow(fromHinge, 1.65))) * featherScale;
    float sideDistance = min(sourceX, 1.0 - sourceX);
    float sideCoverage = smoothstep(-sideWidth * 0.25,
                                    sideWidth * 0.75, sideDistance);
    // Fade *inside* the folded plane, starting farther from the free edge as
    // the lid closes. The old narrow, centered feather left a broad grey cap
    // and still sampled colour at the very top of the projected display.
    float topWidth = (0.025 + foldProgress * 0.70) * featherScale;
    float topCoverage = smoothstep(0.0, topWidth, 1.0 - sourceY);
    float coverage = mix(1.0, sideCoverage * topCoverage,
                         smoothstep(0.0, 0.06, foldProgress));
    if (coverage <= 0.0) {
        output.write(float4(0.0, 0.0, 0.0, 1.0), pixel);
        return;
    }

    // Sample the actual point on the hinged glass. Sampling `screen` here only
    // folds a silhouette over a flat image, which reads as a moving mask.
    float2 textureUV = float2(sourceX, 1.0 - sourceY);

    // Reference wipe.ts: blur grows with distance from the hinge. The
    // horizontal-axis adaptation uses sourceY rather than the phone's x.
    // A focus gradient: the hinge is clear through the middle of the motion,
    // while the free edge approaches the full mip pyramid much sooner.
    // The floor rises late, so the hinge also blurs as the lid nears closure.
    float baseBlur = 0.85 * pow(foldProgress, 3.0);
    float distanceBlur = 4.6 * foldProgress * pow(fromHinge, 1.55);
    float blurArea = clamp(baseBlur + distanceBlur, 0.0, 2.4);
    // maxBlurLOD is a ceiling, not a multiplier for blurArea. Multiplying by
    // the full 0...2.4 range reached the last 1x1 mip level as the lid closed:
    // a wide part of the folded screen became one flat average colour.
    float lod = min((blurArea / 2.4) * uniform.maxBlurLOD,
                    float(source.get_num_mip_levels() - 1));
    float3 colour = textureBicubic(source, sourceSampler, textureUV, lod).rgb;

    // The dark surround comes from the variable-width optical falloff above.
    float blurShade = 1.0 - 0.12 * smoothstep(0.85, 1.5, blurArea);
    float topShade = 1.0 - 0.16 * foldProgress * pow(fromHinge, 1.7);
    colour *= blurShade * topShade * coverage;
    output.write(float4(colour, 1.0), pixel);
}
