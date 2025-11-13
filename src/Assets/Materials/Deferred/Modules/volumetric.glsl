#ifndef VOLUMETRIC_GLSL
#define VOLUMETRIC_GLSL

// =====================================================================================
// Volumetric Lighting Module
// Computes volumetric light scattering using point-to-segment distance calculations.
// Creates atmospheric fog and light ray effects from point light sources.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

// Expected that these UBOs are already declared before including the module:
// uniform light_data { vec4 light_count; mat4 light_transform_array[32];
//                      vec4 light_color_array[32]; vec4 light_properties_array[32]; };

// Local module types to avoid conflicts with external ones
struct VolumetricLightParams {
    int   type;
    vec3  pos;
    vec3  color;
    float powerW;
    float radius;
    float volume_radius;
};

VolumetricLightParams volumetric_readLightParams(int idx){
    VolumetricLightParams L;
    L.type          = int(light_properties_array[idx].x + 0.5);
    L.pos           = light_transform_array[idx][3].xyz;
    L.color         = light_color_array[idx].xyz;
    L.powerW        = max(light_color_array[idx].w, 0.0);
    L.radius        = max(light_properties_array[idx].y, 0.0);
    L.volume_radius = max(light_properties_array[idx].z, 0.0);
    return L;
}

float volumetric_distancePointToSegment(vec3 a, vec3 b, vec3 p) {
    vec3 ab = b - a;
    vec3 ap = p - a;
    float denom = max(dot(ab, ab), 1e-8);
    float t = clamp(dot(ap, ab) / denom, 0.0, 1.0);
    vec3 closest = a + ab * t;
    return length(p - closest);
}

// depthTex is currently unused but passed inside by requirement.
// if desired, can add depth sampling for additional attenuation or shadows.
vec3 volumetric(vec3 P, vec3 camPos, sampler2D depthTex){
    vec3 color = vec3(0.0);

    int count = int(light_count.x + 0.5);
    for (int i = 0; i < count; ++i) {
        VolumetricLightParams Lp = volumetric_readLightParams(i);

        if (Lp.volume_radius <= 0.0)
            continue;

        float d = volumetric_distancePointToSegment(camPos, P, Lp.pos);

        float mask = step(d, Lp.volume_radius);
        float baseIntensity = 0.4 / (1.0 + d * d);
        float intensity = baseIntensity * mask;

        color += Lp.color * intensity * Lp.powerW;
    }

    color /= 40.0;
    return color;
}

#endif // VOLUMETRIC_GLSL
