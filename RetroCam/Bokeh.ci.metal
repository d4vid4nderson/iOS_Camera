// Core Image kernels for the aperture's depth of field (see DepthOfField.swift).
// Built with -fcikernel (the target's Other Metal Compiler / Linker Flags).
#include <CoreImage/CoreImage.h>

extern "C" {
namespace coreimage {

// Give every pixel a weight and carry it in alpha: (rgb * w, w). Bright pixels weigh
// more, so a small light that's out of focus stays a bright disc instead of fading into
// its surroundings, as it does through a lens (the sensor clipped how bright it really was).
// Divided by the largest weight, so every value stays within 0...1 whatever the
// renderer's working format; dofGather divides the weight out again.
float4 dofWeigh(sample_t s, float boost) {
    float luma = dot(s.rgb, float3(0.2126, 0.7152, 0.0722));
    float h = smoothstep(0.6, 1.0, luma);
    float w = (1.0 + boost * h * h) / (1.0 + boost);
    return float4(s.rgb * w, w);
}

// The lens blur. Each pixel gathers `count` points spread evenly over the aperture's
// shape, scaled to this pixel's blur circle: a disc, or a polygon with `blades` sides.
//
//   image       weighted pixels from dofWeigh
//   coc         blur circle per pixel, 0...1 in red
//   scale       pixels of radius at this image size for coc = 1
//   maxGather   the largest radius gathered at this size (larger blurs come from a
//               smaller copy of the image)
//
// A point only counts if its own blur circle reaches this pixel. That keeps a sharp
// subject from smearing into the blurred background behind it.
float4 dofGather(sampler image, sampler coc, float scale, float maxGather,
                 float blades, float rotation, float count, destination dest) {
    float2 dc = dest.coord();
    float radius = min(coc.sample(coc.transform(dc)).r * scale, maxGather);
    float4 sum = image.sample(image.transform(dc));
    if (radius > 0.35) {
        int n = int(count);
        float side = 6.2831853 / max(blades, 1.0);
        for (int i = 0; i < n; i++) {
            float turn = float(i) * 2.3999632;            // golden angle: an even spiral
            float reach = sqrt((float(i) + 0.5) / float(n));
            if (blades >= 3.0) {
                // Pull the disc in to a regular polygon's edge.
                reach *= cos(side * 0.5) / cos(fmod(turn, side) - side * 0.5);
            }
            float d = reach * radius;
            float angle = turn + rotation;
            float2 p = dc + float2(cos(angle), sin(angle)) * d;
            float theirs = coc.sample(coc.transform(p)).r * scale;
            float reaches = clamp(theirs - d + 1.0, 0.0, 1.0);
            sum += image.sample(image.transform(p)) * reaches;
        }
    }
    return float4(sum.rgb / max(sum.a, 0.0001), 1.0);
}

}
}
