--!strict
local Drawing = require("./drawingHelper")

type ObjectDrawer = {
	DrawGizmos: (transform: Transform, mode: number) -> (),
}
local ObjectDrawer = {} :: ObjectDrawer

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
