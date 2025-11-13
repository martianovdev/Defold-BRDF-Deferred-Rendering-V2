// =====================================================================================
// Rectangular Light Shape Module
// Specular reflection calculations for rectangular area lights with proper shape masking.
// Uses solid angle integration and GGX BRDF for physically accurate reflections.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================
// --- Signed solid angle of triangle (vectors from shading point to triangle vertices)
float RectLightShape_solid_angle_triangle(vec3 a, vec3 b, vec3 c)
{
	// Normalize rays from point to vertices
	vec3 A = normalize(a);
	vec3 B = normalize(b);
	vec3 C = normalize(c);

	// Stable spherical excess calculation
	float denom = 1.0 + dot(A,B) + dot(B,C) + dot(C,A);
	float numer = dot(A, cross(B, C));
	return 2.0 * atan(numer, denom); // signed
}

// --- Solid angle of rectangle as sum of two triangles
float RectLightShape_solid_angle_rectangle(vec3 v0, vec3 v1, vec3 v2, vec3 v3)
{
	// In different configurations traversal order can give negative sign.
	// Take sum of absolutes to avoid losing energy due to vertex orientation.
	float w1 = abs(RectLightShape_solid_angle_triangle(v0, v1, v2));
	float w2 = abs(RectLightShape_solid_angle_triangle(v0, v2, v3));
	return w1 + w2; // Ω ∈ [0 .. 2π]
}


// ---------------------------------------------
// Helper: axes/center/normal of rectangular panel
// ---------------------------------------------
void RectLightShape_rect_axes_from_mtx(in mat4 mtx,
	out vec3 center,
	out vec3 nL,
	out vec3 xDir, out float hx,
	out vec3 yDir, out float hy)
{
	vec3 xAxis = mtx[0].xyz; // with scale
	vec3 yAxis = mtx[1].xyz; // with scale
	center     = mtx[3].xyz;

	float lenX = max(length(xAxis), 1e-6);
	float lenY = max(length(yAxis), 1e-6);

	xDir = xAxis / lenX;
	yDir = yAxis / lenY;

	hx = 0.5 * lenX;
	hy = 0.5 * lenY;

	nL = normalize(cross(xAxis, yAxis)); // panel emission "front"
}


vec3 RectLightShape_specular_shape(
	const LightParams L,
	vec3 worldPos,
	vec3 surfaceNormal,
	vec3 viewDir,
	float roughness,
	vec3 F0
){
	// Panel geometry in stable form
	vec3 C, nL, xDir, yDir;
	float hx, hy;
	RectLightShape_rect_axes_from_mtx(L.mtx, C, nL, xDir, hx, yDir, hy);

	// If point is "behind" panel relative to its front - contribution is zero
	float signFront = dot(nL, worldPos - C);
	if (signFront <= 0.0) return vec3(0.0);

	// Reflected direction (safe normalization)
	vec3 R = util_safeNormalize(reflect(-viewDir, surfaceNormal));

	// Ray must look toward panel front
	float denom = dot(R, nL);
	if (denom >= -1e-5) return vec3(0.0);

	// Offset point to avoid self-intersection and artifacts on panel itself
	float scaleRef = max(hx, hy);
	vec3  wp = worldPos + surfaceNormal * max(1e-5, 1e-4 * scaleRef);

	// Intersection of specular ray with panel plane
	float t = dot(C - wp, nL) / denom;
	if (t <= 0.0) return vec3(0.0);

	vec3 hit = wp + R * t;

	// Local coordinates of hit on panel (along panel X/Y axes)
	vec3 rel = hit - C;
	float u = dot(rel, xDir);
	float v = dot(rel, yDir);

	// Soft contour edges in world units, depend on roughness and size
	float softU = max(hx * roughness * 0.0, 1e-6);
	float softV = max(hy * roughness * 0.0, 1e-6);

	// "Inside rectangle" mask with smoothing
	float wU = 1.0 - smoothstep(hx - softU, hx + softU, abs(u));
	float wV = 1.0 - smoothstep(hy - softV, hy + softV, abs(v));
	float shapeMask = wU * wV;
	if (shapeMask <= 0.0) return vec3(0.0);

	// Direction to light (to hit point on panel)
	vec3 Ldir  = util_safeNormalize(hit - wp);
	float NdotL = util_saturateFloat(dot(surfaceNormal, Ldir));
	float NdotV = util_saturateFloat(dot(surfaceNormal, viewDir));
	if (NdotL <= 0.0 || NdotV <= 0.0) return vec3(0.0);

	// Panel emits forward: emission cosine in chosen direction
	float emitCos = max(dot(nL, -Ldir), 0.0);
	if (emitCos <= 0.0) return vec3(0.0);

	// GGX / Cook-Torrance (without LUT)
	float a   = max(roughness * roughness, 1e-3);
	float a2  = a * a;

	vec3  H    = util_safeNormalize(viewDir + Ldir);
	float NdotH = util_saturateFloat(dot(surfaceNormal, H));
	float VdotH = util_saturateFloat(dot(viewDir, H));

	float denomD = (NdotH*NdotH)*(a2 - 1.0) + 1.0;
	float D = a2 / max(PI * denomD * denomD, 1e-6);

	float k = 0.5 * a; // Smith GGX-Schlick
	float Gv = NdotV / (NdotV * (1.0 - k) + k);
	float Gl = NdotL / (NdotL * (1.0 - k) + k);
	float G  = Gv * Gl;

	vec3  F  = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
	vec3  specBRDF = (D * G * F) / max(4.0 * NdotL * NdotV, 1e-6);

	// Scale by solid angle Ω of rectangle (accounts for size and distance)
	vec3 p0, p1, p2, p3, nTmp;
	getRectCorners(L.mtx, p0, p1, p2, p3, nTmp);
	float omega = RectLightShape_solid_angle_rectangle(p0 - wp, p1 - wp, p2 - wp, p3 - wp); // ∈ [0..2π]
	float omegaNorm = omega * (1.0 / (2.0 * PI)); // normalize

	// Result: shape (shapeMask), energy scale (omega), panel front (emitCos)
	vec3 result = specBRDF * L.color * L.intensity * emitCos * omegaNorm * shapeMask;

	// Protection from random spikes (grazing/numerical)
	return clamp(result, vec3(0.0), vec3(1e4));
}