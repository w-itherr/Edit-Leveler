--!strict

type DrawingHelper = {
	DrawFace: (point0: Vec3, point1: Vec3, point2: Vec3, point3: Vec3, colour: LinearColor) -> (),
	DrawPolygon: (points: {}, colour: LinearColor) -> (),
	DrawCircle: (
		radius: number,
		position: Vec3,
		upDirection: Vec3,
		rightDirection: Vec3,
		r: number,
		g: number,
		b: number
	) -> (),
}
local DrawingHelper = {} :: DrawingHelper

function DrawingHelper.DrawFace(point0: Vec3, point1: Vec3, point2: Vec3, point3: Vec3, colour: LinearColor) -- bottom left, top left, bottom right, top right
	WorldDraw.drawTriangle(point0, point1, point2, colour, 0)
	WorldDraw.drawTriangle(point1, point2, point3, colour, 0)
end

function DrawingHelper.DrawPolygon(points: {}, colour: LinearColor)
	local center = Vec3.new(0, 0, 0)
	for _, point in ipairs(points) do
		center = center + point
	end
	center = center / #points

	for i = 1, #points do
		local nextIndex = (i % #points) + 1
		WorldDraw.drawTriangle(center, points[i], points[nextIndex], colour, 0)
	end
end

function DrawingHelper.DrawCircle(
	radius: number,
	position: Vec3,
	upDirection: Vec3,
	rightDirection: Vec3,
	r: number,
	g: number,
	b: number
)
	local prevPoint = nil

	for theta = 0, math.pi * 2, math.pi / 16 do
		local pointPos = upDirection * math.sin(theta) + rightDirection * math.cos(theta)
		local newPoint = position + pointPos * radius

		if prevPoint then
			WorldDraw.drawLine(prevPoint, newPoint, r, g, b, 5, 0)
		end

		prevPoint = newPoint
	end

	local firstPoint = position + (upDirection * math.sin(0) + rightDirection * math.cos(0)) * radius
	WorldDraw.drawLine(prevPoint, firstPoint, r, g, b, 5, 0)
end

return DrawingHelper
