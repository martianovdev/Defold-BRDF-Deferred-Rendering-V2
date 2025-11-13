// =====================================================================================
// Shadow Mapping Module
// Cubemap shadow mapping implementation with soft shadows and gnomonic distortion compensation.
// Supports shadow atlas packing and per-light shadow map sampling.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

// -----------------------------------------------------------------------------
// Global atlas configuration
// -----------------------------------------------------------------------------
const ivec2 ATLAS_SIZE = ivec2(2000, 2000); // full atlas size (px)
const int   FACE_SIZE  = 200;               // single cube face size (px)
const ivec2 ATLAS_GRID = ATLAS_SIZE / FACE_SIZE; // number of cells along (x,y)

// -----------------------------------------------------------------------------
// Direction → local UV [0..1] transformation for given face
// Face order: +X, -X, +Y, -Y, +Z, -Z
// -----------------------------------------------------------------------------
vec2 shadow_getUVForCubeFace(vec3 direction, int faceIndex) {
	vec2 uv = vec2(0.0);
	vec3 absDir = abs(direction);

	if (faceIndex == 0) {       // +X
		uv = vec2( direction.z,  direction.y) / absDir.x;
	} else if (faceIndex == 1){ // -X
		uv = vec2(-direction.z,  direction.y) / absDir.x;
	} else if (faceIndex == 2){ // +Y
		uv = vec2(-direction.x, -direction.z) / absDir.y;
	} else if (faceIndex == 3){ // -Y
		uv = vec2(-direction.x,  direction.z) / absDir.y;
	} else if (faceIndex == 4){ // +Z
		uv = vec2(-direction.x,  direction.y) / absDir.z;
	} else {                    // -Z
		uv = vec2( direction.x,  direction.y) / absDir.z;
	}

	return uv * 0.5 + 0.5; // [-1..1] → [0..1]
}

// -----------------------------------------------------------------------------
// More stable face selection (without >= to avoid jitter on equal components)
// -----------------------------------------------------------------------------
int shadow_getCubeFaceIndex(vec3 direction) {
	vec3 a = abs(direction);
	if (a.x > a.y && a.x > a.z) return (direction.x > 0.0) ? 0 : 1; // ±X
	if (a.y > a.x && a.y > a.z) return (direction.y > 0.0) ? 2 : 3; // ±Y
	return (direction.z > 0.0) ? 4 : 5;                              // ±Z
}

// -----------------------------------------------------------------------------
// Gnomonic distortion compensation: "1 texel" step in UV → almost
// constant angular step around current direction
// dθ/du ≈ 1/(1+u^2) ⇒ to keep dθ ~ const, multiply UV offsets by (1+u^2)
// -----------------------------------------------------------------------------
vec2 shadow_equalAngleTexel(vec2 uvLocal) {
	vec2 p = uvLocal * 2.0 - 1.0;        // [-1..1] on face plane
	vec2 aniso = 1.0 + p * p;            // (1 + u^2, 1 + v^2)
	return aniso / float(FACE_SIZE);     // effective "texel step" in UV
}

// -----------------------------------------------------------------------------
// Local UV [0..1] → global atlas UV [0..1] (row-major packing)
// Includes padding at face edges and Y inversion for OpenGL
// -----------------------------------------------------------------------------
vec2 shadow_localToAtlasUV(vec2 uvLocal, int faceIndex, int cubemapIndex) {
	int COLS = ATLAS_GRID.x;
	int ROWS = ATLAS_GRID.y;

	int globalIndex = cubemapIndex * 6 + faceIndex;
	if (globalIndex < 0 || globalIndex >= COLS * ROWS) return vec2(0.0);

	int gy_top = globalIndex / COLS;
	int gx     = globalIndex - gy_top * COLS;
	int gy_gl  = (ROWS - 1) - gy_top; // Y flip

	vec2 cellOffsetPx = vec2(float(gx), float(gy_gl)) * float(FACE_SIZE);

	const float padPx = 0.5;
	vec2 cellSizePx   = vec2(float(FACE_SIZE));
	vec2 padLocal     = vec2(padPx) / cellSizePx;

	vec2 uvClamped = clamp(uvLocal, padLocal, 1.0 - padLocal);
	vec2 atlasUV   = (cellOffsetPx + uvClamped * cellSizePx) / vec2(ATLAS_SIZE);
	return atlasUV;
}

// -----------------------------------------------------------------------------
// Reconstruct direction from local UV and face index
// -----------------------------------------------------------------------------
vec3 shadow_dirFromFaceUV(vec2 uvLocal, int faceIndex) {
	vec2 p = uvLocal * 2.0 - 1.0;

	if (faceIndex == 0) {       // +X
		return normalize(vec3( 1.0,  p.y,  p.x));
	} else if (faceIndex == 1){ // -X
		return normalize(vec3(-1.0,  p.y, -p.x));
	} else if (faceIndex == 2){ // +Y
		return normalize(vec3(-p.x,  1.0, -p.y));
	} else if (faceIndex == 3){ // -Y
		return normalize(vec3(-p.x, -1.0,  p.y));
	} else if (faceIndex == 4){ // +Z
		return normalize(vec3(-p.x,  p.y,  1.0));
	} else {                    // -Z
		return normalize(vec3( p.x,  p.y, -1.0));
	}
}

bool uv_outside01(vec2 uv) {
	return (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0);
}

// -----------------------------------------------------------------------------
// Sample from atlas with face "stitching" (if outside [0..1], jump to adjacent face)
// -----------------------------------------------------------------------------
vec4 shadow_sampleAtlasStitched(
	sampler2D shadowAtlas,
	vec2 uvLocalMaybeOutside,
	int faceIndex,
	int cubemapIndex
){
	int  f  = faceIndex;
	vec2 uv = uvLocalMaybeOutside;

	if (uv_outside01(uv)) {
		vec3 dir = shadow_dirFromFaceUV(uv, f);
		f  = shadow_getCubeFaceIndex(dir);
		uv = shadow_getUVForCubeFace(dir, f);
	}

	vec2 atlasUV = shadow_localToAtlasUV(uv, f, cubemapIndex);
	return texture(shadowAtlas, atlasUV);
}

// -----------------------------------------------------------------------------
// Simple stable hash from screen coordinates (for sample randomization)
// -----------------------------------------------------------------------------
float hash12(vec2 p) {
	vec3 p3  = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Poisson disk offsets (normalized, ~radius 1)
const vec2 POISSON[12] = vec2[12](
	vec2( 0.00,  -0.58), vec2( 0.34,  0.10), vec2(-0.25,  0.22),
	vec2(-0.41, -0.27), vec2( 0.14, -0.14), vec2( 0.71, -0.10),
	vec2(-0.65,  0.12), vec2(-0.11,  0.58), vec2( 0.31,  0.57),
	vec2(-0.27, -0.61), vec2( 0.56, -0.47), vec2(-0.58,  0.52)
);

// -----------------------------------------------------------------------------
// World size of one texel on cube face at distance r (90° FOV)
// -----------------------------------------------------------------------------
float shadow_worldTexelSize(float r) {
	return (2.0 * r) / float(FACE_SIZE);
}

// -----------------------------------------------------------------------------
// Dynamic bias in world units (constant + slope-dependent)
// -----------------------------------------------------------------------------
float shadow_computeBias(vec3 N, vec3 L_toFrag, float distanceToFrag) {
	vec3 L = normalize(L_toFrag);
	float ndotl = max(dot(N, -L), 0.0);

	float texelWorld = shadow_worldTexelSize(distanceToFrag);
	float constBias  = 0.2 * texelWorld;             // ~0.35 texels
	float slopeBias  = 1.00 * (1.0 - ndotl) * texelWorld; // up to ~1 texel
	return constBias + slopeBias;
}

// -----------------------------------------------------------------------------
// Stochastic PCF in local face coordinates (seam stitching enabled)
// -----------------------------------------------------------------------------
float shadow_PCF_stochastic(
	sampler2D shadowAtlas,
	vec2 uvLocal,
	int faceIndex,
	int cubemapIndex,
	float currentDepth,
	float bias
){
	float radiusTex = 2.5; // radius in "texels" (as before)

	// INSTEAD OF vec2 localTexel = vec2(1.0 / float(FACE_SIZE));
	// take angle-equivalent step depending on position on face
	vec2 localTexel = shadow_equalAngleTexel(uvLocal);

	float ang = hash12(gl_FragCoord.xy) * 6.28318530718;
	vec2  c = vec2(cos(ang), sin(ang));

	float acc = 0.0;
	for (int i = 0; i < 12; ++i) {
		vec2 o = POISSON[i];

		// Rotate disk as before
		vec2 oRot = vec2(o.x * c.x - o.y * c.y, o.x * c.y + o.y * c.x);

		// But now step along axes is different: compensate distortion
		vec2 ofsLocal = oRot * (radiusTex * localTexel);

		float d = shadow_sampleAtlasStitched(
			shadowAtlas,
			uvLocal + ofsLocal,    // without clamp - "stitching" will handle transition
			faceIndex,
			cubemapIndex
		).r;

		acc += (currentDepth <= d + bias) ? 1.0 : 0.0;
	}
	return acc / 12.0;
}

// ---------- helpers ----------
float shadow_fetchDepth(sampler2D atlas, vec2 atlasUV) {
	// Better this way (LOD=0) to avoid catching mip blending at edges
	return textureLod(atlas, atlasUV, 0.0).r;
}

vec2 shadow_atlasUVFromDir(vec3 dir, int cubemapIndex, out int faceIndex) {
	faceIndex = shadow_getCubeFaceIndex(dir);
	vec2 uvLocal = shadow_getUVForCubeFace(dir, faceIndex);
	return shadow_localToAtlasUV(uvLocal, faceIndex, cubemapIndex);
}

// Soft comparison instead of hard step: smooths "rings"
float shadow_compareSoft(float currentDepth, float storedDepth, float bias, float eps) {
	// x > 0 ⇒ light; x < 0 ⇒ shadow
	float x = (storedDepth + bias) - currentDepth;
	return smoothstep(-eps, eps, x);
}

// ONB around direction (tangent/bitangent) for sphere offsets
void basis_from_dir(in vec3 n, out vec3 t, out vec3 b) {
	vec3 up = (abs(n.z) < 0.999) ? vec3(0,0,1) : vec3(0,1,0);
	t = normalize(cross(up, n));
	b = cross(n, t);
}

// ---------- PCF on sphere (isotropic and seamless) ----------
float shadow_PCF_spherical(
	sampler2D shadowAtlas,
	vec3 dir,                 // NORMALIZED direction from light to fragment
	int cubemapIndex,
	float currentDepth,       // distance light→frag
	float bias)
	{
		// Angular step size of one texel ~ 2/FACE_SIZE radians (at face center).
		// Constant works stably, main thing - offset in DIRECTION SPACE.
		const float thetaPerTexel = 2.0 / float(FACE_SIZE);
		const float radiusTex     = 2.5;               // "kernel radius" in texels
		float rAng = thetaPerTexel * radiusTex;        // angular kernel radius

		// Per-pixel disk rotation
		float ang = hash12(gl_FragCoord.xy) * 6.28318530718;
		mat2  rot = mat2(cos(ang), -sin(ang),
		sin(ang),  cos(ang));

		vec3 T, B; basis_from_dir(dir, T, B);

		// Thickness of "threshold" zone for compareSoft - ~¾ world texel at current distance.
		float eps = 0.75 * shadow_worldTexelSize(currentDepth);

		float acc = 0.0;
		for (int i = 0; i < 12; ++i) {
			vec2 o = rot * POISSON[i]; // uniform disk
			// Small angles: offset on sphere via tangent plane
			vec3 dirOff = normalize(dir + (T * o.x + B * o.y) * tan(rAng));

			int f; vec2 atlasUV = shadow_atlasUVFromDir(dirOff, cubemapIndex, f);
			float sd = shadow_fetchDepth(shadowAtlas, atlasUV);

			acc += shadow_compareSoft(currentDepth, sd, bias, eps);
		}
		return acc / 12.0;
	}
	

// -----------------------------------------------------------------------------
// Main soft shadow function for point light source in atlas
// -----------------------------------------------------------------------------
float shadow_computeSoft(
	vec3 fragWorldPos,
	vec3 fragWorldNormal,
	vec3 lightWorldPos,
	sampler2D shadowAtlas,
	int cubemapIndex)
	{
		vec3 LtoF = fragWorldPos - lightWorldPos;
		float currentDepth = length(LtoF);
		vec3 dir = LtoF / max(currentDepth, 1e-6); // normalize without NaN

		float bias = shadow_computeBias(fragWorldNormal, LtoF, currentDepth);

		return shadow_PCF_spherical(
			shadowAtlas, dir, cubemapIndex, currentDepth, bias
		);
	}
	