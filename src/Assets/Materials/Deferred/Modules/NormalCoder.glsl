// =====================================================================================
// Normal Coder Module
// Octahedral normal encoding/decoding for efficient G-buffer storage.
// Encodes 3D normals into 2D coordinates using octahedral mapping.
//
// Author: Mikhail Martianov | martianov.tech
// =====================================================================================

// -------- Helpers --------

// Safe reciprocal (avoids division by zero by clamping the denominator)
float normalCoder_safeRcp(float x) { 
	return 1.0 / max(x, 1e-8); 
}

// Returns the sign of a 2D vector as (+1 or -1) for each component
vec2 normalCoder_sign2(vec2 v) { 
	return vec2(v.x >= 0.0 ? 1.0 : -1.0, 
		v.y >= 0.0 ? 1.0 : -1.0); 
	}


	// -------- OCT ENCODE ([-1..1]^3 -> [0..1]^2) --------
	// Encodes a normalized 3D vector into 2D using octahedral mapping.
	// Branchless implementation; distributes error uniformly across the sphere.
	vec2 normalCoder_octEncode(vec3 normalWorld)
	{
		// Ensure the input normal is unit length
		normalWorld = normalize(normalWorld);

		// Project the normal onto the octahedron surface (using L1 norm)
		float invL1 = normalCoder_safeRcp(abs(normalWorld.x) + abs(normalWorld.y) + abs(normalWorld.z));
		normalWorld *= invL1;

		// Handle the "wrap" for the lower hemisphere (z < 0)
		// This folds the bottom half of the sphere onto the top
		vec2 encoded = (normalWorld.z >= 0.0)
		? normalWorld.xy
		: (vec2(1.0 - abs(normalWorld.y), 1.0 - abs(normalWorld.x)) * 
		normalCoder_sign2(normalWorld.xy));

		// Remap from [-1..1] range to [0..1]
		return encoded * 0.5 + 0.5;
	}


	// -------- OCT DECODE ([0..1]^2 -> [-1..1]^3) --------
	// Decodes a 2D octahedral-encoded vector back into a normalized 3D normal
	vec3 normalCoder_octDecode(vec2 encoded01)
	{
		// Convert from [0..1] range back to [-1..1]
		vec2 f = encoded01 * 2.0 - 1.0;

		// Initial reconstruction of the normal (before fixing hemisphere wrap)
		vec3 normalWorld = vec3(f.x, f.y, 1.0 - abs(f.x) - abs(f.y));

		// Branchless fix for the case when z < 0
		// Pushes the vector back into the valid hemisphere
		float t = max(-normalWorld.z, 0.0);
		normalWorld.x += (normalWorld.x >= 0.0 ? -t :  t);
		normalWorld.y += (normalWorld.y >= 0.0 ? -t :  t);

		// Normalize to ensure unit length
		return normalize(normalWorld);
	}