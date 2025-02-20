#include <metal_stdlib>
using namespace metal;



#include <metal_stdlib>
using namespace metal;

struct MixerParameters
{
    float2 pipPosition;
    float2 pipSize;
};

constant sampler kBilinearSampler(filter::linear,  coord::pixel, address::clamp_to_edge);

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Add a uniform for the scale
struct Uniforms {
    float2 scale;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                              constant Uniforms &u [[buffer(0)]]) {
    VertexOut out;

    // Full-screen quad coordinates
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };

    float2 texCoords[4] = {
        float2(0, 1),
        float2(1, 1),
        float2(0, 0),
        float2(1, 0)
    };

    // Apply the scale to the positions
    out.position = float4(positions[vertexID] * u.scale, 0, 1);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> fullScreenTexture [[texture(0)]]) {
    constexpr sampler textureSampler(filter::linear, address::clamp_to_edge);
    return fullScreenTexture.sample(textureSampler, in.texCoord);
}
