// =====================================================================================
// Filmic Tonemapping Module
// Advanced tone mapping operators: ACES, Filmic (Uncharted 2), and AgX implementations.
// Provides exposure, contrast, saturation, and gamma correction controls.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

// === Tone mapper selection constants ===
const int FILMIC_TM_ACES   = 0;
const int FILMIC_TM_FILMIC = 1;
const int FILMIC_TM_AGX    = 2;
const int FILMIC_TONE_MAP_MODE = FILMIC_TM_AGX;  // <-- main switch

// === User settings (tweak to match scene style) ===
const float FILMIC_EXPOSURE   = 0.03;   // global brightness scale (≈0.8..2.0)
const float FILMIC_WHITE_PT   = 11.2;   // white point for Filmic normalization
const float FILMIC_SATURATION = 0.8;    // 0=grayscale, 1=as is, >1=more vivid
const float FILMIC_CONTRAST   = 1.5;   // gentle contrast boost (~1.0..1.1)
const float FILMIC_MIDGRAY    = 0.2;    // pivot point for contrast adjustment
const float FILMIC_GAMMA_OUT  = 1.1;   // output gamma (e.g. 2.2, 2.4; 1.0 = linear)

// --------------------------------------------------------
// Helper functions
// --------------------------------------------------------
vec3 filmic_applyContrast(vec3 color, float contrast, float pivot) {
	// Contrast adjustment around a pivot (typically midgray)
	return (color - vec3(pivot)) * contrast + vec3(pivot);
}

vec3 filmic_applySaturation(vec3 color, float saturation) {
	// Adjust saturation relative to luminance
	const vec3 lumaW = vec3(0.2126, 0.7152, 0.0722); // Rec.709 weights
	float luma = dot(color, lumaW);
	return mix(vec3(luma), color, saturation);
}

vec3 filmic_toSRGB(vec3 linearColor, float gammaVal) {
	// Convert from linear to sRGB-like gamma space
	return pow(max(linearColor, 0.0), vec3(1.0 / gammaVal));
}

// --------------------------------------------------------
// ACES (Narkowicz fit approximation)
// --------------------------------------------------------
vec3 filmic_ACESFitted(vec3 x) {
	// Input transform (RGB to ACES color space)
	const mat3 ACESInputMat = mat3(
		0.59719, 0.35458, 0.04823,
		0.07600, 0.90834, 0.01566,
		0.02840, 0.13383, 0.83777
	);

	// Output transform (ACES back to RGB)
	const mat3 ACESOutputMat = mat3(
		1.60475, -0.53108, -0.07367,
		-0.10208,  1.10813, -0.00605,
		-0.00327, -0.07276,  1.07602
	);

	// Tone mapping curve (fitted polynomial rational approximation)
	x = ACESInputMat * x;
	vec3 a = x * (x + 0.0245786) - 0.000090537;
	vec3 b = x * (0.983729 * x + 0.4329510) + 0.238081;
	x = a / b;
	x = ACESOutputMat * x;

	// Clamp to display range
	return clamp(x, 0.0, 1.0);
}

// --------------------------------------------------------
// Filmic (Hable curve from Uncharted 2)
// --------------------------------------------------------
float filmic_FilmicCurve(float x) {
	// Rational polynomial curve, S-shaped, film-like roll-off
	const float A = 0.22;
	const float B = 0.30;
	const float C = 0.10;
	const float D = 0.20;
	const float E = 0.01;
	const float F = 0.30;
	return ((x * (A * x + C * B) + D * E) /
	(x * (A * x + B) + D * F)) - E / F;
}

vec3 filmic_FilmicHable(vec3 x, float whitePoint) {
	// Normalize curve so whitePoint maps to 1.0
	float whiteScale = 1.0 / filmic_FilmicCurve(whitePoint);
	x = max(x, 0.0);
	return clamp(vec3(
		filmic_FilmicCurve(x.r),
		filmic_FilmicCurve(x.g),
		filmic_FilmicCurve(x.b)) * whiteScale, 0.0, 1.0);
	}

// --------------------------------------------------------
// AgX (Blender / Troy Sobotka)
// --------------------------------------------------------
float filmic_AgXCurve(float x) {
	// Logistic-like S-curve in log2 domain
	const float minEv = -12.47393; // lower exposure bound (~-12 EV)
	const float maxEv =  4.026069; // upper exposure bound (~+4 EV)

	// Convert to log2 EV space
	float log2x = log2(max(x, 1e-6));
	float t = clamp((log2x - minEv) / (maxEv - minEv), 0.0, 1.0);

	// Smooth sigmoid interpolation (ease-in-out cubic)
	return t * t * (3.0 - 2.0 * t);
}

vec3 filmic_AgX(vec3 x) {
	// Apply AgX tone curve per channel
	return vec3(
		filmic_AgXCurve(x.r),
		filmic_AgXCurve(x.g),
		filmic_AgXCurve(x.b)
	);
}

// --------------------------------------------------------
// Main tone mapping entry point
// --------------------------------------------------------
vec3 filmic_ToneMap(vec3 hdrColor) {
	// Apply exposure
	vec3 color = hdrColor * FILMIC_EXPOSURE;

	// Select tone mapping operator
	if (FILMIC_TONE_MAP_MODE == FILMIC_TM_ACES) {
		color = filmic_ACESFitted(color);
	} else if (FILMIC_TONE_MAP_MODE == FILMIC_TM_FILMIC) {
		color = filmic_FilmicHable(color, FILMIC_WHITE_PT);
	} else { // FILMIC_TM_AGX
		color = filmic_AgX(color);
	}

	// Optional grading adjustments
	color = filmic_applyContrast(color, FILMIC_CONTRAST, FILMIC_MIDGRAY);
	color = filmic_applySaturation(color, FILMIC_SATURATION);

	// Final gamma correction to output space
	color = filmic_toSRGB(color, FILMIC_GAMMA_OUT);

	return clamp(color, 0.0, 1.0);
}
