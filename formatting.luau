--!strict

type Formatting = {
	Vec3ToString: (vec3: Vec3) -> string,
	LinearColourToQuat: (colour: LinearColor) -> Quat,
}
local Formatting = {} :: Formatting

function Formatting.Vec3ToString(vec3: Vec3): string
	return "X="
		.. string.format("%.3f", vec3.x)
		.. " Y="
		.. string.format("%.3f", vec3.y)
		.. " Z="
		.. string.format("%.3f", vec3.z)
end

function Formatting.LinearColourToQuat(colour: LinearColor): Quat
	local c = colour :: any

	local redIndex = #c == 3 and 0 or 4
	return Quat.new(c[redIndex], c[1], c[2], c[3])
end

return Formatting
