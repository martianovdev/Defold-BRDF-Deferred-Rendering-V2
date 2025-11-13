#version 140

// =====================================================================================
// Tiled Lighting Fragment Shader
// Computes per-tile light masks for deferred rendering optimization.
// Reconstructs world positions from depth, evaluates shadowed lights, and encodes
// active light indices into a 24-bit mask stored in R32F format.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

// ========================= I/O & UNIFORMS =========================
in vec2 var_texcoord0;

uniform sampler2D texture_normal;      // Normal buffer
uniform sampler2D texture_shadowmap;   // Shadow map array/atlas
uniform sampler2D texture_depth_full;  // Full-resolution depth

// Render target and input sizes
uniform data {
    uniform vec4 size;    
};

// Camera transforms
uniform camera {
    uniform mediump mat4 mtx_camera_projection;
    uniform mediump mat4 mtx_camera_projection_inv;
    uniform mediump mat4 mtx_camera_view;
    uniform mediump mat4 mtx_camera_view_inv;
};

// Light data (supports up to 32 lights)
uniform light_data {
    uniform vec4 light_count;                       // .x = number of active lights
    uniform mat4 light_transform_array[32];         // world transforms
    uniform vec4 light_color_array[32];             // RGB intensity
    uniform vec4 light_properties_array[32];        // .x = type, other params
};

// Primary render target
out float out_color;

// --- MASK output (R32F)
// GLSL 140: multiple outputs are bound via glBindFragDataLocation in the application.
// Just declaring here is enough.
out float out_mask;

// ========================= HELPERS =========================
float saturate(float x) { return clamp(x, 0.0, 1.0); }

// Reconstructs view-space position from depth
vec3 reconstructViewPos(vec2 uv, float deviceDepth) {
    vec2 ndc = uv * 2.0 - 1.0;
    vec4 clip = vec4(ndc, deviceDepth * 2.0 - 1.0, 1.0);
    vec4 view = mtx_camera_projection_inv * clip;
    return (view / max(view.w, 1e-6)).xyz;
}

// Reconstructs world-space position from depth
vec3 reconstructWorldPos(vec2 uv, float deviceDepth) {
    vec3 v = reconstructViewPos(uv, deviceDepth);
    return (mtx_camera_view_inv * vec4(v, 1.0)).xyz;
}

// ========================= LIGHT =========================
struct LightParams {
    int   type;   // Light type (point, spot, etc.)
    vec3  pos;    // Light world-space position
    vec3  color;  // Light RGB intensity
    bool shadows;
};

// Extract light parameters from uniform arrays
LightParams readLightParams(int idx) {
    LightParams L;
    L.type  = int(light_properties_array[idx].x + 0.5);
    L.pos   = light_transform_array[idx][3].xyz;
    L.color = light_color_array[idx].xyz;
    L.shadows = bool(light_properties_array[idx].w);
    return L;
}

// External include: implements shadow computation
#include "/src/Assets/Materials/Deferred/Modules/lighting_shadow.glsl"

// ========================= MAIN =========================
void main() {
    vec2 uv = gl_FragCoord.xy / size.xy;

    // Fetch depth & normal from G-buffer
    float deviceDepth = texture(texture_depth_full, uv).x;
    vec3  N = texture(texture_normal, uv).xyz * 2.0 - 1.0;
    vec3  P = reconstructWorldPos(uv, deviceDepth);

    // Initialize 24-bit mask (stored in a uint)
    uint mask24 = 0u;

    int count = int(light_count.x + 0.5);
    for (int i = 0; i < count; ++i) {
        LightParams Lp = readLightParams(i);

        // Compute shadow contribution (defined in lighting_shadow.glsl)
        float shadow = 1.0;
        if(Lp.shadows){
            shadow = shadow_computeSoft(P, N, Lp.pos, texture_shadowmap, i);
        }


        if (shadow > 0.0) {
            if (i < 24) {
                // Set bit for this light index (0..23 only)
                mask24 |= (1u << uint(i));
            }
        }
    }

    // Output:
    // - RGB not used (set to 0)
    // - A stores the exact integer mask (converted to float)
    out_color = float(mask24);
}
