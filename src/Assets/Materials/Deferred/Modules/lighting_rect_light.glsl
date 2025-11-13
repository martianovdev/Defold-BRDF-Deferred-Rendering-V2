// =====================================================================================
// Rectangular Area Light Module
// Physically-based rectangular area light implementation using solid angle integration.
// Supports diffuse lighting with proper geometric attenuation and facing calculations.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

float RectLight_solid_angle_triangle(vec3 a, vec3 b, vec3 c, vec3 P) {
	vec3 A = normalize(a - P);
	vec3 B = normalize(b - P);
	vec3 C = normalize(c - P);

	float denom = 1.0 + dot(A,B) + dot(B,C) + dot(C,A);
	float numer = dot(A, cross(B, C));
	return 2.0 * atan(numer, denom);
}


float solidAngleRect(vec3 p0, vec3 p1, vec3 p2, vec3 p3, vec3 P) {
	float w1 = RectLight_solid_angle_triangle(p0, p1, p2, P);
	float w2 = RectLight_solid_angle_triangle(p0, p2, p3, P);
	return abs(w1 + w2); // in case of vertex order
}

// ---------- Helpers: TBN + clip to horizon ----------
void RectLight_make_tbn(in vec3 N, out vec3 T, out vec3 B){
	vec3 up = (abs(N.z) < 0.999) ? vec3(0.0,0.0,1.0) : vec3(0.0,1.0,0.0);
	T = normalize(cross(up, N));
	B = cross(N, T);
}

// Clip rectangle to local half-space "horizon" z>=0
int RectLight_clip_quad_to_horizon(vec3 v0, vec3 v1, vec3 v2, vec3 v3, out vec3 outV[8]){
	vec3 inV[4]; inV[0]=v0; inV[1]=v1; inV[2]=v2; inV[3]=v3;
	int outCount = 0;
	vec3 prev = inV[3];
	bool prevIn = prev.z > 0.0;
	for(int i=0;i<4;i++){
		vec3 curr = inV[i];
		bool currIn = curr.z > 0.0;

		if(currIn != prevIn){
			float t = prev.z / (prev.z - curr.z + 1e-8);
			vec3 I = prev + (curr - prev) * t;
			outV[outCount++] = I;
		}
		if(currIn){
			outV[outCount++] = curr;
		}
		prev = curr; prevIn = currIn;
	}
	return outCount;
}

// Stable vector integration along edge of spherical polygon
vec3 RectLight_integrate_edge_vec(vec3 a, vec3 b){
	vec3 va = normalize(a);
	vec3 vb = normalize(b);
	vec3 c  = cross(va, vb);
	float l = length(c);
	if(l < 1e-8) return vec3(0.0);
	float phi = atan(l, dot(va, vb)); // atan2(|cross|, dot)
	return (c / l) * phi;
}

// ---------- Helpers: panel geometry ----------
void RectLight_get_rect_corners(in mat4 mtx, out vec3 c0, out vec3 c1, out vec3 c2, out vec3 c3, out vec3 nL)
{
	vec3 axisX  = mtx[0].xyz;   // includes scale
	vec3 axisY  = mtx[1].xyz;
	vec3 center = mtx[3].xyz;

	vec3 hx = axisX * 0.5;
	vec3 hy = axisY * 0.5;

	// Order around perimeter
	c0 = center - hx - hy;
	c1 = center + hx - hy;
	c2 = center + hx + hy;
	c3 = center - hx + hy;

	// Panel normal from cross of axes (correct direction even with non-uniform scale)
	nL = normalize(cross(axisX, axisY));
}


// ---------- Main uniform rectangular panel shader ----------
vec3 RectLight_diffuse(
	const LightParams L,
	vec3 worldPos,
	vec3 surfaceNormal
){
	// --- Tweaks ---
	const float FACING_FULL_ON_DEG = 10.0; // 0..10° - full brightness
	const float FACING_ZERO_DEG    = 180.0; // 85..180° - zero
	const float FACING_EXP         = 1.5;   // >1.0 - sharper
	float R = max(L.radiusSurface, 1e-6);

	// --- Panel geometry ---
	vec3 p0,p1,p2,p3,nL;
	RectLight_get_rect_corners(L.mtx, p0,p1,p2,p3, nL);
	vec3 C = L.mtx[3].xyz;

	// [FIX] Panel emits FORWARD along +nL. Mask selects points IN FRONT of panel.
	float side     = dot(worldPos - C, nL);         // >0 - in front of panel "face"
	float softness = max(1e-5, 0.25 * R);
	float frontMask = smoothstep(-softness, softness, side); // 1 in front, 0 behind

	// --- Local basis at point ---
	vec3 N = normalize(surfaceNormal);
	vec3 T,B; RectLight_make_tbn(N, T, B);
	mat3 W2L = mat3(T, B, N);

	// Light exit from self-shadowing
	vec3 P = worldPos + N * 1e-4;

	// Rectangle vertices in receiver local space
	vec3 v0 = W2L * (p0 - P);
	vec3 v1 = W2L * (p1 - P);
	vec3 v2 = W2L * (p2 - P);
	vec3 v3 = W2L * (p3 - P);

	// Clip visible part of source relative to receiver (z>=0)
	vec3 poly[8];
	int n = RectLight_clip_quad_to_horizon(v0,v1,v2,v3, poly);
	if (n == 0) return vec3(0.0);

	// Projected solid angle integral: E ∈ [0..π]
	vec3 V = vec3(0.0);
	for (int i=0;i<n;++i){
		vec3 a = poly[i];
		vec3 b = poly[(i+1)%n];
		V += RectLight_integrate_edge_vec(a, b);
	}
	float E = max(V.z, 0.0);

	// Panel area (world)
	float lenX = max(length(L.mtx[0].xyz), 1e-6);
	float lenY = max(length(L.mtx[1].xyz), 1e-6);
	float area = lenX * lenY;

	// Radial "hack" without breaking solid angle physics
	vec3  uDir = L.mtx[0].xyz / lenX;
	vec3  vDir = L.mtx[1].xyz / lenY;
	float hxLen = 0.5 * lenX;
	float hyLen = 0.5 * lenY;
	vec3  r   = worldPos - C;
	float u   = clamp(dot(r, uDir), -hxLen, hxLen);
	float v   = clamp(dot(r, vDir), -hyLen, hyLen);
	vec3  closest = C + uDir * u + vDir * v;
	float metric = length(worldPos - closest);
	float t = clamp(metric / R, 0.0, 1.0);
	float radialMask = pow(1.0 - t, 2.0);

	// [FIX] "Facing" now aligned with panel front (+nL), not -nL
	float cosFull = cos(radians(FACING_FULL_ON_DEG));
	float cosZero = cos(radians(FACING_ZERO_DEG));
	float d = clamp(dot(N, nL), -1.0, 1.0);
	float facing = pow(smoothstep(cosZero, cosFull, d), FACING_EXP);

	// Normalization: intensity divided by area, E/π - half-space fraction
	float phys = (L.intensity / area) * (E / 3.14159265);

	// [FIX] Use frontMask instead of backMask
	float brightness = phys * frontMask * facing * radialMask;

	return vec3(brightness);
}


