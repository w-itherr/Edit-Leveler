--!strict

local Controlling = {}

local controllingAxis = 0
local isControlling = false

local lastMouseScreenPos: Vec3 = nil

local frozenAxisLocal = Vec3.zeroVector
local frozenOrigPoint = Vec3.zeroVector
local frozenStartRotation = Quat.new(0, 0, 0, 1)
local frozenStartHitPoint = Vec3.zeroVector

local translateRadius = 100

function Controlling.GetIfMouseIsIn2Pos(camPos: Vec3, rayDir: Vec3, A: Vec3, B: Vec3)
	local AB = B - A
	local AO = camPos - A
	local dotABAB = AB:dot(AB)
	local dotABDir = AB:dot(rayDir)
	local dotABAO = AB:dot(AO)
	local dotDirAO = rayDir:dot(AO)
	local denom = dotABAB - dotABDir * dotABDir
	local t, u
	if math.abs(denom) < 1e-6 then
		t = 0
		u = dotABAO / dotABAB
	else
		t = (dotABDir * dotABAO - dotABAB * dotDirAO) / denom
		u = (dotABAO - dotABDir * dotDirAO) / denom
	end
	if t < 0 then
		t = 0
	end
	u = math.max(0, math.min(1, u))
	local delta = (camPos + rayDir * t) - (A + AB * u)

	return delta:dot(delta) <= translateRadius
end

function Controlling.RayPlaneIntersection(rayOrigin: Vec3, rayDir: Vec3, planePoint: Vec3, planeNormal): (Vec3, number)
	local denom = planeNormal:dot(rayDir)

	if math.abs(denom) < 1e-6 then
		return Vec3.zeroVector, -1
	end

	local t = (planePoint - rayOrigin):dot(planeNormal) / denom

	if t < 0 then
		return Vec3.zeroVector, -1
	end

	return rayOrigin + rayDir * t, t
end

function Controlling.IsMouseOnRotationRing(center: Vec3, normal: Vec3, radius: number, thickness: number): boolean
	local camPos = camera.position
	local rayDir = (camera:castRayFromMouse().position - camPos):getSafeNormal()

	local hitPoint, t = Controlling.RayPlaneIntersection(camPos, rayDir, center, normal)
	if hitPoint == Vec3.zeroVector and t == -1 then
		return false
	end

	local distFromCenter = (hitPoint - center):length()

	if math.abs(distFromCenter - radius) <= thickness then
		return true
	end

	return false
end

function Controlling.SignedAngle(a: Vec3, b: Vec3, axis: Vec3): number
	local cross = a:cross(b)
	local dot = a:dot(b)
	return math.atan2(cross:dot(axis), dot)
end

function QuatFromAxisAngle(axis: Vec3, angle: number): Quat
	local half = angle * 0.5
	local s = math.sin(half)
	local n = axis:getSafeNormal()
	return Quat.new(n.x * s, n.y * s, n.z * s, math.cos(half)):normalize()
end

function Controlling.GetMovementAlongLine(lineStart: Vec3, lineEnd: Vec3): number
	local camPos = camera.position
	local rayDir = (camera:castRayFromMouse().position - camPos):getSafeNormal()

	local lineDir = (lineEnd - lineStart):getSafeNormal()
	local lineLength = (lineEnd - lineStart):length()

	local viewDir = (camPos - lineStart):getSafeNormal()
	local planeNormal = lineDir:cross(viewDir):cross(lineDir):getSafeNormal()

	local currentHit, _ = Controlling.RayPlaneIntersection(camPos, rayDir, lineStart, planeNormal)

	if currentHit == Vec3.zeroVector then
		return 0
	end

	local currentT = (currentHit - lineStart):dot(lineDir)
	currentT = math.max(0, math.min(lineLength, currentT))

	if lastMouseScreenPos == Vec3.zeroVector then
		lastMouseScreenPos = currentHit
		return 0
	end

	local previousT = (lastMouseScreenPos - lineStart):dot(lineDir)
	previousT = math.max(0, math.min(lineLength, previousT))

	local movement = currentT - previousT
	lastMouseScreenPos = currentHit

	return movement
end

function Controlling.ControlTranslateGizmo(object: {
	transform: Transform,
	name: string,
	folder: string,
	colour: LinearColor,
	type: number,
})
	local origPoint = object.transform.position

	local forward = object.transform.rotation:getForwardVector()
	local right = object.transform.rotation:getRightVector()
	local up = object.transform.rotation:getUpVector()

	local forwardEnd = origPoint + forward * 50
	local rightEnd = origPoint + right * 50
	local upEnd = origPoint + up * 50

	if isControlling and Input.getKey(Input.Key.LeftMouseButton) then
		local axisDir: Vec3
		local lineStart: Vec3
		local lineEnd: Vec3

		local movementforwardEnd = origPoint + forward * 50000
		local movementrightEnd = origPoint + right * 50000
		local movementupEnd = origPoint + up * 50000

		if controllingAxis == 0 then
			axisDir = forward
			lineStart = origPoint
			lineEnd = movementforwardEnd
		elseif controllingAxis == 1 then
			axisDir = right
			lineStart = origPoint
			lineEnd = movementrightEnd
		else
			axisDir = up
			lineStart = origPoint
			lineEnd = movementupEnd
		end

		local movement = Controlling.GetMovementAlongLine(lineStart, lineEnd)

		object.transform.position += axisDir * movement
	else
		lastMouseScreenPos = Vec3.zeroVector

		local camPos = camera.position
		local rayDir = (camera:castRayFromMouse().position - camPos):getSafeNormal()

		local isUp = Controlling.GetIfMouseIsIn2Pos(camPos, rayDir, origPoint, upEnd)
		local isRight = Controlling.GetIfMouseIsIn2Pos(camPos, rayDir, origPoint, rightEnd)
		local isForward = Controlling.GetIfMouseIsIn2Pos(camPos, rayDir, origPoint, forwardEnd)

		if isUp then
			controllingAxis = 2
			isControlling = true
		elseif isRight then
			controllingAxis = 1
			isControlling = true
		elseif isForward then
			controllingAxis = 0
			isControlling = true
		else
			isControlling = false
		end
	end

	return not isControlling
end

function Controlling.ControlRotateGizmo(object: {
	transform: Transform,
	name: string,
	folder: string,
	colour: LinearColor,
	type: number,
})
	local origPoint = object.transform.position
	local up = object.transform.rotation:getUpVector()
	local right = object.transform.rotation:getRightVector()
	local forward = object.transform.rotation:getForwardVector()

	local isX = Controlling.IsMouseOnRotationRing(origPoint, right, 50, 5) -- blue ring
	local isY = Controlling.IsMouseOnRotationRing(origPoint, up, 50, 5) -- green ring
	local isZ = Controlling.IsMouseOnRotationRing(origPoint, forward, 50, 5) -- red ring

	if isControlling and Input.getKey(Input.Key.LeftMouseButton) then
		local camPos = camera.position
		local rayDir = (camera:castRayFromMouse().position - camPos):getSafeNormal()

		local worldAxis = frozenStartRotation:rotateVector(frozenAxisLocal)

		local hitPoint, _ = Controlling.RayPlaneIntersection(camPos, rayDir, frozenOrigPoint, worldAxis)

		if hitPoint ~= Vec3.zeroVector and frozenStartHitPoint ~= Vec3.zeroVector then
			local a = (frozenStartHitPoint - frozenOrigPoint):getSafeNormal()
			local b = (hitPoint - frozenOrigPoint):getSafeNormal()
			local angle = Controlling.SignedAngle(a, b, worldAxis)

			object.transform.rotation = frozenStartRotation * QuatFromAxisAngle(frozenAxisLocal, angle)
		end
	else
		local camPos = camera.position
		local rayDir = (camera:castRayFromMouse().position - camPos):getSafeNormal()

		local function BeginDrag(axisIndex: number, localAxis: Vec3)
			controllingAxis = axisIndex
			isControlling = true
			frozenOrigPoint = origPoint
			frozenStartRotation = object.transform.rotation
			frozenAxisLocal = localAxis

			local worldAxis = frozenStartRotation:rotateVector(localAxis)
			local hitPoint, t = Controlling.RayPlaneIntersection(camPos, rayDir, origPoint, worldAxis)
			if hitPoint ~= Vec3.zeroVector and t ~= -1 then
				frozenStartHitPoint = hitPoint
			end
		end

		if isX then
			BeginDrag(0, Vec3.new(0, 1, 0))
		elseif isY then
			BeginDrag(1, Vec3.new(0, 0, 1))
		elseif isZ then
			BeginDrag(2, Vec3.new(1, 0, 0))
		else
			isControlling = false
		end
	end

	return not isControlling
end

function Controlling.ControlScaleGizmo(object: {
	transform: Transform,
	name: string,
	folder: string,
	colour: LinearColor,
	type: number,
})
	local origPoint = object.transform.position

	local forward = object.transform.rotation:getForwardVector()
	local right = object.transform.rotation:getRightVector()
	local up = object.transform.rotation:getUpVector()

	if isControlling and Input.getKey(Input.Key.LeftMouseButton) then
		local lineStart: Vec3
		local lineEnd: Vec3
		local scaleComponent: string

		local movementforwardEnd = origPoint + forward * 50000
		local movementrightEnd = origPoint + right * 50000
		local movementupEnd = origPoint + up * 50000

		if controllingAxis == 0 then
			lineStart = origPoint
			lineEnd = movementforwardEnd
			scaleComponent = "z"
		elseif controllingAxis == 1 then
			lineStart = origPoint
			lineEnd = movementrightEnd
			scaleComponent = "x"
		else
			lineStart = origPoint
			lineEnd = movementupEnd
			scaleComponent = "y"
		end

		local movement = Controlling.GetMovementAlongLine(lineStart, lineEnd)
		local scaleDelta = movement / 50

		if scaleComponent == "x" then
			object.transform.scale.x = math.max(0, object.transform.scale.x + scaleDelta)
		elseif scaleComponent == "y" then
			object.transform.scale.y = math.max(0, object.transform.scale.y + scaleDelta)
		else
			object.transform.scale.z = math.max(0, object.transform.scale.z + scaleDelta)
		end
	else
		lastMouseScreenPos = Vec3.zeroVector
		local camPos = camera.position
		local rayDir = (camera:castRayFromMouse().position - camPos):getSafeNormal()

		local isUp = Controlling.GetIfMouseIsIn2Pos(camPos, rayDir, origPoint, origPoint + up * 50)
		local isForward = Controlling.GetIfMouseIsIn2Pos(camPos, rayDir, origPoint, origPoint + forward * 50)
		local isRight = Controlling.GetIfMouseIsIn2Pos(camPos, rayDir, origPoint, origPoint + right * 50)

		if isUp then
			isControlling = true
			controllingAxis = 2
		elseif isRight then
			isControlling = true
			controllingAxis = 1
		elseif isForward then
			isControlling = true
			controllingAxis = 0
		else
			isControlling = false
		end
	end

	return not isControlling
end

return Controlling
