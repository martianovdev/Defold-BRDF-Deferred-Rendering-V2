local M = {}

function M.generate_kernel(kernelSize)
	local ssaoKernel = {}
	for i = 1, kernelSize do
		local kernel = vmath.vector4(
		math.random() * 2 - 1, 
		math.random() * 2 - 1, 
		math.random(), 0)
		kernel = vmath.normalize(kernel)
		local scale = (i - 1) / kernelSize
		scale = vmath.lerp(scale * scale, 0.1, 1.0)
		kernel = kernel * scale
		table.insert(ssaoKernel, kernel)
	end
	return ssaoKernel
end

function M.generate_noise(noiseSize)
	local ssaoNoise = {}
	for i = 1, noiseSize do
		local noise = vmath.vector4(
		math.random() * 2 - 1,
		math.random() * 2 - 1,
		0, 0)

		noise = vmath.normalize(noise)
		table.insert(ssaoNoise, noise)
	end
	return ssaoNoise;
end

return M