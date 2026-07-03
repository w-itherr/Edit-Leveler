--!strict
local Drawing = require("./drawing")

type ObjectDrawer = {
	DrawCube: (transform: Transform, colour: LinearColor, outline: boolean) -> (),
	DrawCylinder: (transform: Transform, colour: LinearColor, outline: boolean, sides: number) -> (),
	DrawGizmos: (transform: Transform, mode: number) -> (),
}
local ObjectDrawer = {} :: ObjectDrawer

function ObjectDrawer.DrawCube(transform: Transform, colour: LinearColor, outline: boolean)
	local rotation = transform.rotation
	local scale = transform.scale
	local center = transform.position

	local upDir = rotation:getUpVector()
	local rightDir = rotation:getRightVector()
	local forwardDir = rotation:getForwardVector()

	local up = upDir * (scale.y * 100)
	local right = rightDir * (scale.x * 100)
	local forwards = forwardDir * (scale.z * 100)

	local bottomBackLeft = center
	local bottomBackRight = center + right
	local bottomFrontLeft = center + forwards
	local bottomFrontRight = bottomFrontLeft + right
	local topBackLeft = center + up
	local topBackRight = topBackLeft + right
	local topFrontLeft = topBackLeft + forwards
	local topFrontRight = topFrontLeft + right

	Drawing.DrawFace(bottomBackLeft, topBackLeft, bottomBackRight, topBackRight, colour) -- back
	Drawing.DrawFace(bottomFrontLeft, topFrontLeft, bottomFrontRight, topFrontRight, colour) -- front
	Drawing.DrawFace(bottomBackLeft, topBackLeft, bottomFrontLeft, topFrontLeft, colour) -- left
	Drawing.DrawFace(bottomBackRight, topBackRight, bottomFrontRight, topFrontRight, colour) -- right

	Drawing.DrawFace(topBackLeft, topBackRight, topFrontLeft, topFrontRight, colour) -- top
	Drawing.DrawFace(bottomBackLeft, bottomBackRight, bottomFrontLeft, bottomFrontRight, colour) -- bottom--

	if outline then
		local additionalSize = 0.75
		local halfAdd = additionalSize * 0.5

		local outlinecenter = center - (upDir + rightDir + forwardDir) * halfAdd

		local outlineup = (upDir * ((scale.y * 100) + additionalSize))
		local outlineright = rightDir * ((scale.x * 100) + additionalSize)
		local outlineforwards = forwardDir * ((scale.z * 100) + additionalSize)

		local outlinebottomBackLeft = outlinecenter
		local outlinebottomBackRight = outlinecenter + outlineright
		local outlinebottomFrontLeft = outlinecenter + outlineforwards
		local outlinebottomFrontRight = outlinebottomFrontLeft + outlineright

		local outlinetopBackLeft = outlinecenter + outlineup
		local outlinetopBackRight = outlinetopBackLeft + outlineright
		local outlinetopFrontLeft = outlinetopBackLeft + outlineforwards
		local outlinetopFrontRight = outlinetopFrontLeft + outlineright

		local size = 1
		local r, g, b = 0.8, 0.2, 0.2

		WorldDraw.drawLine(outlinebottomBackLeft, outlinebottomBackRight, r, g, b, size, 0)
		WorldDraw.drawLine(outlinebottomBackLeft, outlinebottomFrontLeft, r, g, b, size, 0)
		WorldDraw.drawLine(outlinebottomFrontRight, outlinebottomBackRight, r, g, b, size, 0)
		WorldDraw.drawLine(outlinebottomFrontRight, outlinebottomFrontLeft, r, g, b, size, 0)
		WorldDraw.drawLine(outlinetopBackLeft, outlinetopBackRight, r, g, b, size, 0)
		WorldDraw.drawLine(outlinetopBackLeft, outlinetopFrontLeft, r, g, b, size, 0)
		WorldDraw.drawLine(outlinetopFrontRight, outlinetopBackRight, r, g, b, size, 0)
		WorldDraw.drawLine(outlinetopFrontRight, outlinetopFrontLeft, r, g, b, size, 0)

		WorldDraw.drawLine(outlinebottomBackLeft, outlinetopBackLeft, r, g, b, size, 0)
		WorldDraw.drawLine(outlinebottomFrontRight, outlinetopFrontRight, r, g, b, size, 0)
		WorldDraw.drawLine(outlinebottomBackRight, outlinetopBackRight, r, g, b, size, 0)
		WorldDraw.drawLine(outlinebottomFrontLeft, outlinetopFrontLeft, r, g, b, size, 0)
	end
end

function ObjectDrawer.DrawCylinder(transform: Transform, colour: LinearColor, outline: boolean, sides: number)
	local scale = transform.scale
	local rotation = transform.rotation
	local pivotPoint = transform.position

	local rightDir = rotation:getRightVector()
	local forwardDir = rotation:getForwardVector()
	local upDir = rotation:getUpVector()

	local right = rightDir * (scale.x * 100)
	local up = upDir * (scale.y * 100)
	local forward = forwardDir * (scale.z * 100)

	local center = pivotPoint + (right * 0.5) + (up * 0.5) + (forward * 0.5)

	local width = scale.x * 100
	local height = scale.y * 100
	local depth = scale.z * 100

	local radiusX = width / 2
	local radiusZ = depth / 2
	local halfHeight = height / 2

	local topPoints = {}
	local bottomPoints = {}

	local angleStep = (math.pi * 2) / sides

	for i = 0, sides - 1 do
		local angle = i * angleStep

		local localX = math.cos(angle) * radiusX
		local localZ = math.sin(angle) * radiusZ

		local topWorldPoint = center + (rightDir * localX) + (upDir * halfHeight) + (forwardDir * localZ)
		local bottomWorldPoint = center + (rightDir * localX) + (upDir * -halfHeight) + (forwardDir * localZ)

		table.insert(topPoints, topWorldPoint)
		table.insert(bottomPoints, bottomWorldPoint)
	end

	for i = 1, sides do
		local nextIndex = (i % sides) + 1

		local bottomLeft = bottomPoints[i]
		local bottomRight = bottomPoints[nextIndex]
		local topLeft = topPoints[i]
		local topRight = topPoints[nextIndex]

		Drawing.DrawFace(bottomLeft, topLeft, bottomRight, topRight, colour)
	end

	Drawing.DrawPolygon(topPoints, colour)
	Drawing.DrawPolygon(bottomPoints, colour)

	if outline then
		local size = 1

		local additionalSize = 0.75

		local outlineCenter = transform.position
			- (upDir * (additionalSize / 2))
			- (rightDir * (additionalSize / 2))
			- (forwardDir * (additionalSize / 2))

		local outlineWidth = (scale.x * 100) + additionalSize
		local outlineHeight = (scale.y * 100) + additionalSize
		local outlineDepth = (scale.z * 100) + additionalSize

		local outlineRight = rightDir * outlineWidth
		local outlineUp = upDir * outlineHeight
		local outlineForward = forwardDir * outlineDepth

		local actualOutlineCenter = outlineCenter + (outlineRight * 0.5) + (outlineUp * 0.5) + (outlineForward * 0.5)

		local outlineRadiusX = outlineWidth / 2
		local outlineRadiusZ = outlineDepth / 2
		local outlineHalfHeight = outlineHeight / 2

		local outlineTopPoints = {}
		local outlineBottomPoints = {}

		for i = 0, sides - 1 do
			local angle = i * angleStep

			local localX = math.cos(angle) * outlineRadiusX
			local localZ = math.sin(angle) * outlineRadiusZ

			local topPoint = actualOutlineCenter
				+ (rightDir * localX)
				+ (upDir * outlineHalfHeight)
				+ (forwardDir * localZ)
			local bottomPoint = actualOutlineCenter
				+ (rightDir * localX)
				+ (upDir * -outlineHalfHeight)
				+ (forwardDir * localZ)

			table.insert(outlineTopPoints, topPoint)
			table.insert(outlineBottomPoints, bottomPoint)
		end

		local r = 0.8
		local g = 0.2
		local b = 0.2

		for i = 1, sides do
			WorldDraw.drawLine(outlineBottomPoints[i], outlineTopPoints[i], r, g, b, size, 0)
		end

		for i = 1, sides do
			local nextIndex = (i % sides) + 1
			WorldDraw.drawLine(outlineTopPoints[i], outlineTopPoints[nextIndex], r, g, b, size, 0)
			WorldDraw.drawLine(outlineBottomPoints[i], outlineBottomPoints[nextIndex], r, g, b, size, 0)
		end

		if sides <= 8 then
			local topCapCenter = actualOutlineCenter + (upDir * outlineHalfHeight)
			local bottomCapCenter = actualOutlineCenter + (upDir * -outlineHalfHeight)

			for i = 1, sides do
				WorldDraw.drawLine(topCapCenter, outlineTopPoints[i], r, g, b, size, 0)
				WorldDraw.drawLine(bottomCapCenter, outlineBottomPoints[i], r, g, b, size, 0)
			end
		end
	end
end

function ObjectDrawer.DrawGizmos(transform: Transform, mode: number) -- 0 = Translation, 1 = Rotation, 2 = Scale
	local dist = 1.75
	local origPoint = transform.position
		- transform.rotation:getUpVector() * dist
		- transform.rotation:getForwardVector() * dist
		- transform.rotation:getRightVector() * dist

	local upVec = origPoint + transform.rotation:getUpVector() * 50
	local forwardVec = origPoint + transform.rotation:getForwardVector() * 50
	local rightVec = origPoint + transform.rotation:getRightVector() * 50

	if mode == 0 then
		WorldDraw.drawLine(origPoint, upVec, 0, 0, 1, 5, 0) -- up
		WorldDraw.drawLine(origPoint, forwardVec, 1, 0, 0, 5, 0) -- forwards
		WorldDraw.drawLine(origPoint, rightVec, 0, 1, 0, 5, 0) -- right
	elseif mode == 1 then
		Drawing.DrawCircle(
			50,
			origPoint,
			transform.rotation:getUpVector(),
			transform.rotation:getRightVector(),
			1,
			0,
			0
		)
		Drawing.DrawCircle(
			50,
			origPoint,
			transform.rotation:getForwardVector(),
			transform.rotation:getUpVector(),
			0,
			1,
			0
		)
		Drawing.DrawCircle(
			50,
			origPoint,
			transform.rotation:getRightVector(),
			transform.rotation:getForwardVector(),
			0,
			0,
			1
		)
	else
		WorldDraw.drawLine(origPoint, upVec, 0, 0, 1, 5, 0) -- up
		WorldDraw.drawLine(origPoint, forwardVec, 1, 0, 0, 5, 0) -- forwards
		WorldDraw.drawLine(origPoint, rightVec, 0, 1, 0, 5, 0) -- right
		local scale = 10000

		local upScale = scale / camera:getSmoothedPosition():distance(upVec)
		local forwardScale = scale / camera:getSmoothedPosition():distance(forwardVec)
		local rightScale = scale / camera:getSmoothedPosition():distance(rightVec)

		WorldDraw.drawPoint(upVec, 0, 0, 1, upScale, 0)
		WorldDraw.drawPoint(forwardVec, 1, 0, 0, forwardScale, 0)
		WorldDraw.drawPoint(rightVec, 0, 1, 0, rightScale, 0)
	end
end

return ObjectDrawer
