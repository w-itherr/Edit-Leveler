--!strict

type Freecam = {
	setRotAndGrav: (rot: Vec3, gravity: Quat) -> (),
	frecamtick: (dt: number, rotateCam: boolean) -> (),
}
local Freecam = {} :: Freecam

-- this is just the old freecam code but modified to remove some bits :]

local forwardKey = Input.Key.W
local backwardKey = Input.Key.S
local leftKey = Input.Key.A
local rightKey = Input.Key.D
local upKey = Input.Key.E
local downKey = Input.Key.Q
--- This moves the camera up and down along the gravity vector instead of local up
local verticalMovementModifier = Input.Key.LeftAlt

local pitchUpKey = Input.Key.Up
local pitchDownKey = Input.Key.Down
local yawLeftKey = Input.Key.Left
local yawRightKey = Input.Key.Right

-- Tap these keys to adjust the camera movement speed
local fastKey = Input.Key.LeftShift
local slowKey = Input.Key.LeftControl

local zoomSpeedKb = 5

local minFov = 10
local maxFov = 160

local rotSpeed = 180
--- How much the zoom level affects view rotation speed control. 0 to disable the effect.
local fovRotSpeedMultiplier = 2

local moveSpeed = 1600
local maxMoveSpeed = 10000
local minMoveSpeed = 500
--- How fast the speed adjustment buttons affect the camera speed
local speedAdjustmentRate = 1
local mouseSensitivity = 3.6
-- Should be a number between 0 and 1, with 1 being infinitely smooth (the camera won't rotate)
local lookSmoothness = 0
local lookInputTarget = Vec3.zeroVector

-- Change apparent gravity direction quickly when looking around, or slowly passively to avoid disorientation
local gravityChaseSpeed = 6
local gravitySlowChaseSpeed = 0.5

local rotEuler = Vec3.zeroVector -- this if for freecam
local gravityChaser = gravity.upRotation

function Freecam.setRotAndGrav(rot: Vec3, gravity: Quat)
	rotEuler = rot
	gravityChaser = gravity
end

function Freecam.frecamtick(dt, rotateCam: boolean)
	local forward = camera.rotation:getForwardVector()
	local right = camera.rotation:getRightVector()
	local up = camera.rotation:getUpVector()

	if Input.getKey(fastKey) then
		moveSpeed *= (1 + speedAdjustmentRate * dt)
		if moveSpeed < minMoveSpeed then
			moveSpeed = minMoveSpeed
		end
	elseif Input.getKey(slowKey) then
		moveSpeed *= (1 - speedAdjustmentRate * dt)

		if moveSpeed > maxMoveSpeed then
			moveSpeed = maxMoveSpeed
		end
	end

	camera.fieldOfView -= Input.getAnalog(Input.Key.MouseWheelAxis) * zoomSpeedKb
	camera.fieldOfView = math.clamp(camera.fieldOfView, minFov, maxFov)

	local input = Vec3.zeroVector

	if Input.getKey(forwardKey) then
		input += forward
	end
	if Input.getKey(backwardKey) then
		input -= forward
	end
	if Input.getKey(rightKey) then
		input += right
	end
	if Input.getKey(leftKey) then
		input -= right
	end
	if Input.getKey(upKey) then
		if Input.getKey(verticalMovementModifier) then
			input += gravity.upDirection
		else
			input += up
		end
	end
	if Input.getKey(downKey) then
		if Input.getKey(verticalMovementModifier) then
			input -= gravity.upDirection
		else
			input -= up
		end
	end

	local adjustedRotSpeed = fovRotSpeedMultiplier * (camera.fieldOfView - 90) / 90 + rotSpeed
	local adjustedMouseSensitivity = fovRotSpeedMultiplier * (camera.fieldOfView - 90) / 90 + mouseSensitivity
	local adjustedLookSmoothness = 1 - (1 - lookSmoothness) ^ 3
	local lookInputTargetDelta = Vec3.zeroVector
	local rollAngle = -rotEuler.x * math.pi / 180.0

	if rotateCam then
		local mouse = Input.getMouseDelta()
		if mouse and mouse.x then
			lookInputTargetDelta.z += mouse.x * adjustedMouseSensitivity
			lookInputTargetDelta.y += mouse.y * adjustedMouseSensitivity
		end
	end

	if Input.getKey(yawRightKey) then
		lookInputTargetDelta.z += adjustedRotSpeed * dt
	end
	if Input.getKey(yawLeftKey) then
		lookInputTargetDelta.z -= adjustedRotSpeed * dt
	end
	if Input.getKey(pitchUpKey) then
		lookInputTargetDelta.y += adjustedRotSpeed * dt
	end
	if Input.getKey(pitchDownKey) then
		lookInputTargetDelta.y -= adjustedRotSpeed * dt
	end

	-- Smoothing
	local rollAdjustedInput = Vec3.new(
		lookInputTargetDelta.x,
		lookInputTargetDelta.y * math.cos(rollAngle) + lookInputTargetDelta.z * math.sin(rollAngle),
		lookInputTargetDelta.z * math.cos(rollAngle) - lookInputTargetDelta.y * math.sin(rollAngle)
	)
	lookInputTarget += rollAdjustedInput
	local nextLookDiff = lookInputTarget * math.min((1 - adjustedLookSmoothness) * dt * 60, 1)

	if gravityChaser ~= gravity.upRotation and gravity.strength ~= 0 then
		local inputTotal = nextLookDiff:length()
		local nextGravityChaser =
			Quat.slerp(gravityChaser, gravity.upRotation, (inputTotal * gravityChaseSpeed + gravitySlowChaseSpeed) * dt)

		local nextRotation = nextGravityChaser:inverse()
			* Quat.fromXZ(forward, nextGravityChaser:rotateVector(Vec3.new(0, 0, 1)))
		rotEuler = nextRotation:euler() + Vec3.new(rotEuler.x, 0, 0) -- preserve existing roll
		gravityChaser = nextGravityChaser
	end

	rotEuler += nextLookDiff
	lookInputTarget -= nextLookDiff

	if rotEuler.y > 89.9 then
		rotEuler.y = 89.9
	end
	if rotEuler.y < -89.9 then
		rotEuler.y = -89.9
	end

	camera.position += input * moveSpeed * dt
	camera.rotation = gravityChaser * Quat.fromEuler(rotEuler.x, rotEuler.y, rotEuler.z)
end

return Freecam
