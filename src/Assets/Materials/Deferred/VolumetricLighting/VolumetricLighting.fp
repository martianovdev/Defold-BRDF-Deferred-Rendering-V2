#version 140

// =====================================================================================
// Volumetric Lighting Fragment Shader
// Computes volumetric light scattering effects using point-to-segment distance calculations.
// Creates atmospheric light rays and fog-like effects from light sources.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

in vec2 var_texcoord0;

uniform sampler2D texture_depth_full;

// Render target and sizes
uniform data {
    uniform vec4 size;       // xy = framebuffer size
};

// Camera
uniform camera {
    uniform mediump mat4 mtx_camera_projection;
    uniform mediump mat4 mtx_camera_projection_inv;
    uniform mediump mat4 mtx_camera_view;
    uniform mediump mat4 mtx_camera_view_inv;
};

// Light sources (up to 32)
uniform light_data {
    uniform vec4 light_count;                       // .x = number of active sources
    uniform mat4 light_transform_array[32];         // world transforms (pos in [3].xyz)
    uniform vec4 light_color_array[32];             // RGB intensity, .w = powerW
    uniform vec4 light_properties_array[32];        // .x = type, .y = radius, .z = volume_radius
};

// Include module
// if you don't have preprocessor include, just inline volumetric.glsl contents here
#include "/src/Assets/Materials/Deferred/Modules/volumetric.glsl"

out vec4 out_color;

// ========================= HELPERS =========================
float saturate(float x) { return clamp(x, 0.0, 1.0); }

vec3 reconstructViewPos(vec2 uv, float deviceDepth) {
    vec2 ndc = uv * 2.0 - 1.0;
    vec4 clip = vec4(ndc, deviceDepth * 2.0 - 1.0, 1.0);
    vec4 view = mtx_camera_projection_inv * clip;
    return (view / max(view.w, 1e-6)).xyz;
}

vec3 reconstructWorldPos(vec2 uv, float deviceDepth) {
    vec3 v = reconstructViewPos(uv, deviceDepth);
    return (mtx_camera_view_inv * vec4(v, 1.0)).xyz;
}

vec3 getCameraWorldPos() {
    return mtx_camera_view_inv[3].xyz;
}

// ========================= MAIN =========================
void main() {
    vec2 uv = gl_FragCoord.xy / size.xy;

    float deviceDepth = texture(texture_depth_full, uv).x;

    vec3 P = reconstructWorldPos(uv, deviceDepth);
    vec3 camPos = getCameraWorldPos();

    // pass sampler to module
    vec3 color = volumetric(P, camPos, texture_depth_full);

    out_color = vec4(color, 1.0);
}
