// =====================================================================================
// Volumetric Lighting Advanced Module
// Advanced volumetric scattering with single scattering integration and line glow effects.
// Implements Henyey-Greenstein phase function and Beer-Lambert transmittance for atmospheric lighting.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

#define PI 3.1415926535897932384626433832795

// Clamp helpers
float volumetric_saturateFloat(float x) { return clamp(x, 0.0, 1.0); }
vec2  util_saturateVec2(vec2 v)   { return clamp(v, 0.0, 1.0); }
vec3  util_saturateVec3(vec3 v)   { return clamp(v, 0.0, 1.0); }

// Safe normalize
vec3 volumetric_safeNormalize(vec3 v) {
	float m2 = max(dot(v, v), EPS);
	return v * inversesqrt(m2);
}


// -------------------------
// Henyey–Greenstein phase function
// cosTheta — angle between view direction and light direction
// g        — anisotropy coefficient (0 = isotropic, >0 = forward scattering)
// -------------------------
float volumetric_phaseHG(float cosTheta, float g) {
	float g2 = g * g;
	float denom = pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
	return (1.0 - g2) / (4.0 * PI * max(denom, 1e-3));
}


// -------------------------
// Segment-sphere intersection test
// A->B segment vs sphere
// Returns entry and exit points if intersection exists
// -------------------------
bool volumetric_segmentSphereIntersection(
	vec3 pointA, vec3 pointB,
	vec3 sphereCenter, float sphereRadius,
	out vec3 pointEnter, out vec3 pointExit)
{
	vec3 d = pointB - pointA;         // segment direction
	vec3 m = pointA - sphereCenter;   // vector from sphere center to point A
	float dd = dot(d, d);
	float md = dot(m, d);
	float mm = dot(m, m);
	float r2 = sphereRadius * sphereRadius;

	// Discriminant of quadratic equation
	float disc = md * md - dd * (mm - r2);
	if (disc < 0.0) return false; // no intersection

	float sdisc = sqrt(disc);
	float t0 = (-md - sdisc) / dd;
	float t1 = (-md + sdisc) / dd;

	// Ensure t0 < t1
	if (t0 > t1) { float tmp = t0; t0 = t1; t1 = tmp; }

	// Clamp entry/exit points to [0,1] segment range
	float tEnter = max(0.0, t0);
	float tExit  = min(1.0, t1);
	if (tEnter > tExit) return false; // no valid overlap

	pointEnter = mix(pointA, pointB, tEnter);
	pointExit  = mix(pointA, pointB, tExit);
	return true;
}


// -------------------------
// Density falloff inside the sphere
// p — point
// c — sphere center
// r — sphere radius
// -------------------------
float volumetric_sphereFalloff(vec3 p, vec3 c, float r) {
	float d = length(p - c) / r;          // normalized distance to center
	float x = volumetric_saturateFloat(1.0 - d); // clamp to [0,1]
	// Smoothstep-like falloff (cubic Hermite)
	return x * x * (3.0 - 2.0 * x);
}


// -------------------------
// Small hash function for jittering samples
// -------------------------
float volumetric_hash12(vec2 p) {
	vec3 p3  = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


// -------------------------
// Volumetric light integration for one source
// camPos         — camera position
// fragPos        — world-space fragment position
// lightPos       — light source position
// lightColor     — RGB light color
// lightIntensity — light power/intensity
// volRadius      — radius of spherical volume
// sigma_s        — scattering coefficient
// sigma_e        — extinction coefficient
// hg_g           — HG phase anisotropy
// out scatterRGB — accumulated scattered color
// out tauOut     — accumulated optical thickness
// -------------------------
void volumetric_integrateForLight(
	vec3 camPos, vec3 fragPos,
	vec3 lightPos,
	vec3 lightColor, float lightIntensity,
	float volRadius,
	float sigma_s, float sigma_e,
	float hg_g,
	out vec3 scatterRGB, out float tauOut)
{
	scatterRGB = vec3(0.0);
	tauOut = 0.0;

	// Find intersection of camera->fragment segment with spherical volume
	vec3 iEnter, iExit;
	if (!volumetric_segmentSphereIntersection(camPos, fragPos, lightPos, volRadius, iEnter, iExit)) {
		return; // no intersection → no contribution
	}

	// Define integration segment
	vec3 segment = iExit - iEnter;
	float segmentLength = length(segment);
	vec3 segmentDir = segment / max(segmentLength, 1e-6);

	// Step control
	const float BASE_STEP = 0.25;
	const int   MAX_STEPS = 2;

	int steps = int(clamp(ceil(segmentLength / BASE_STEP), 2.0, float(MAX_STEPS)));
	float stepLength = segmentLength / float(steps);

	// Jitter for reduced banding
	float jitter = volumetric_hash12(gl_FragCoord.xy + vec2(lightPos.x, lightPos.y));
	float transmittance = 1.0;

	// Integration loop
	for (int s = 0; s < MAX_STEPS; ++s) {
		if (s >= steps) break;

		// Current sample position along segment
		float t = (float(s) + jitter) * stepLength;
		vec3 samplePoint = iEnter + segmentDir * t;

		// Density profile inside sphere
		float density = volumetric_sphereFalloff(samplePoint, lightPos, volRadius);

		// Light attenuation with distance (1 / (1+r^2))
		vec3 lightDir = volumetric_safeNormalize(samplePoint - lightPos);
		float r2  = max(dot(samplePoint - lightPos, samplePoint - lightPos), 1e-4);
		float invAttenuation = 1.0 / (1.0 + r2);

		// Phase function (directional scattering)
		float cosTheta = dot(-segmentDir, -lightDir);
		float phase = volumetric_phaseHG(cosTheta, hg_g);

		// Radiance from light source
		vec3 Li = lightColor * lightIntensity * invAttenuation;

		// Optical thickness and scattering per step
		float deltaTau = sigma_e * density * stepLength;
		float scatterAmt = sigma_s * density * stepLength;

		// Accumulate scattered light contribution
		scatterRGB += transmittance * (Li * phase) * scatterAmt;

		// Update transmittance (Beer-Lambert law)
		transmittance *= exp(-deltaTau);
		tauOut += deltaTau;
	}
}


// -------------------------
// Transversal glow along the ray (line glow)
// Creates a "halo" effect when ray passes near a light
//
// camPos         — camera position
// fragPos        — fragment position
// lightPos       — light source position
// lightColor     — source color
// intensity      — source intensity
// glowRadius     — radius of halo
// glowIntensity  — strength of halo
// tauRef         — optical depth reference for medium absorption
// -------------------------
vec3 volumetric_lineGlow(
	vec3 camPos, vec3 fragPos, vec3 lightPos,
	vec3 lightColor, float intensity,
	float glowRadius, float glowIntensity, float tauRef)
{
	vec3 P1 = camPos;
	vec3 P2 = fragPos;
	vec3 P3 = lightPos;

	vec3 P1P2 = P2 - P1;
	float segLen = max(length(P1P2), 1e-6);
	vec3  P1P2n = P1P2 / segLen; // normalized camera->frag direction
	vec3  P1P3  = P3 - P1;       // vector to light

	// Project light onto camera->frag segment
	float projLen = dot(P1P3, P1P2n);
	vec3  closest =
	(projLen < 0.0)    ? P1 :   // light is "before" segment start
	(projLen > segLen) ? P2 :   // light is "after" segment end
	P1 + P1P2n * projLen;       // otherwise inside

	// Distance from light to ray
	float d = length(P3 - closest);

	// Glow profile falloff
	float t = volumetric_saturateFloat(1.0 - d / glowRadius);
	float profile = t * t;

	// Medium absorption factor
	float mediumFactor = 1.0 - exp(-tauRef);

	// Distance attenuation
	float r2c = max(dot(P3 - closest, P3 - closest), 1e-4);
	float invAtt = 1.0 / (1.0 + r2c);

	// Final glow contribution
	vec3 Li = lightColor * intensity * invAtt;
	return Li * (glowIntensity * profile * mediumFactor);
}
		