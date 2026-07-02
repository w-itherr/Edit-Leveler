--!strict

--[[
	Hello fellow code reader! Please be aware all of this code is really messy but here is a few key things that if you are looking for, hopefully this can help :]
	Everything is split into their own files and the names are a bit confusing but they should be descriptive of what they do!

	Controlling.luau - This handles everything to do with all the gizmos and all the math that this project took just for it to be in a good enough state to release
	Drawing.luau - This is just a simple little library I use here and there for drawing stuff (Faces, Polygons and Circles)
	Editor.luau - This is the file you are in but this brings everything together
	Formatting.luau - This is another library I made but this one is for just converting one type to other
	Freecam.luau - This controls how you move and rotate the camera, taken this code from the anotheraxiom.freecam script and modified to have the features I needed
	ObjectDrawer.luau - This handles everything to do with everything you see on the screen such as; the objects being drawn and the gizmos being drawn

	If you see anything that you think should be changed via code, feel free to tell me in the thread! Just dont be rude about it please :]
	Also everything here was made over a few months of me working on this and then not at really late into the night, so everything WILL be messy lol
]]

local freecam = require("./freecam")
local ObjectDrawer = require("objectDrawer")
local Formatting = require("formatting")
local Freecam = require("freecam")
local Controlling = require("controlling")

local folders = {}
local objects = {}

-- object stuff
local selectedObject = -1
local search = ""
local currentSelectionMode = 0 -- 0 = Translation, 1 = Rotation, 2 = Scale
local objectTypes = {
	{
		Name = "Cube",
		TypeIndex = 1,
		PrevPress = false,
		DrawFunction = function(object, isSelected)
			ObjectDrawer.DrawCube(object.transform, object.colour, isSelected)
		end,
	},
	{
		Name = "Cylinder",
		TypeIndex = 2,
		PrevPress = false,
		DrawFunction = function(object, isSelected)
			ObjectDrawer.DrawCylinder(object.transform, object.colour, isSelected, 16)
		end,
	},
	{
		Name = "Prism",
		TypeIndex = 3,
		PrevPress = false,
		DrawFunction = function(object, isSelected)
			ObjectDrawer.DrawCylinder(object.transform, object.colour, isSelected, 3)
		end,
	},
}

-- Inputs
local lastNKeyPress = false
local prevSpacebarPress = false

---- GUI Views
-- Folder view
local inFolderCreateMode = false
local folderView = 0
local tempFolderName = ""

-- Project view
local inProjectMode = false
local projectView = 0
local saveName = ""
local currentProjectName = ""

-- Freecam
local rotateCam = true

-- Autosave
local timer = 0
local timerStart = 0
local saveTime = 30 -- seconds

-- Other
local isGuiOpen = false

-- Settings
local S_hideGizmosOnUIOpen = true

function onTransitionBegin(transitionInfo: Transition)
	camera.positionSmoothing = 0.02
	camera.rotationSmoothing = 0.02
	camera.fieldOfViewSmoothing = 0.05
	transitionInfo.length = 0
	postProcessSettings.depthOfFieldFocalDistance = 0
	camera.position = Vec3.new(0, 2200, -28500)
	camera.rotation = Quat.fromEuler(0, 0, 90)
	camera.fieldOfView = 70
	freecam.setRotAndGrav(Vec3.new(0, -90, 0), Quat.fromEuler(0, 0, 90))

	timer = DateTime.getCurrentTime().ticks / 10000000
	timerStart = timer + saveTime
end

function RedrawAll()
	WorldDraw.clearAll()

	local cameraPos = camera:getSmoothedPosition()

	local sortedObjects = {}
	for i, object: {
		transform: Transform,
		name: string,
		folder: string,
		colour: LinearColor,
		type: number,
	} in
		ipairs(objects)
	do
		local distance = object.transform.position:distance(cameraPos)

		table.insert(sortedObjects, {
			index = i,
			object = object,
			distance = distance,
		})
	end

	table.sort(sortedObjects, function(a, b)
		return a.distance > b.distance
	end)

	for _, item in ipairs(sortedObjects) do
		local i = item.index
		local object = item.object
		local drawIt = selectedObject == i
		if S_hideGizmosOnUIOpen and not isGuiOpen then
			drawIt = false
		end

		for io, objectType in ipairs(objectTypes) do
			if objectType.TypeIndex == object.type then
				objectType.DrawFunction(object, drawIt)
				break
			end
		end

		if selectedObject == i and drawIt then
			ObjectDrawer.DrawGizmos(object.transform, currentSelectionMode)
		end
	end
end

function DoGizmoControlling()
	if selectedObject ~= -1 then
		local object = objects[selectedObject]

		if currentSelectionMode == 0 then
			rotateCam = Controlling.ControlTranslateGizmo(object)
		elseif currentSelectionMode == 1 then
			rotateCam = Controlling.ControlRotateGizmo(object)
		elseif currentSelectionMode == 2 then
			rotateCam = Controlling.ControlScaleGizmo(object)
		end
	end
end

function tick(dt)
	RedrawAll()
	if not (S_hideGizmosOnUIOpen and not isGuiOpen) then
		DoGizmoControlling()
		Freecam.frecamtick(dt, rotateCam)
	else
		Freecam.frecamtick(dt, true)
	end

	if Input.getKey(Input.Key.N) and not lastNKeyPress then
		local newObj = {
			name = "Object " .. #objects + 1,
			folder = "",
			transform = Transform.identity,
			colour = LinearColor.White,
			type = 1,
		}
		newObj.transform.position = camera.position + camera.rotation:getForwardVector() * 500
		newObj.transform.rotation = gravity.upRotation
		objects[#objects + 1] = newObj
		selectedObject = #objects
	end

	if Input.getKey(Input.Key.F) and selectedObject ~= -1 then
		camera.position = objects[selectedObject].transform.position
			+ objects[selectedObject].transform.rotation:getForwardVector() * -250
			+ objects[selectedObject].transform.rotation:getUpVector() * 250
			+ objects[selectedObject].transform.rotation:getRightVector() * -250
		camera:lookAt(
			objects[selectedObject].transform.position,
			objects[selectedObject].transform.rotation:getUpVector()
		)

		Freecam.setRotAndGrav(camera.rotation:euler(), objects[selectedObject].transform.rotation)
	end

	if Input.getKey(Input.Key.BackSpace) and selectedObject ~= -1 then
		table.remove(objects, selectedObject)
		selectedObject = -1
	end

	if Input.getKey(Input.Key.One) then
		currentSelectionMode = 0
	end
	if Input.getKey(Input.Key.Two) then
		currentSelectionMode = 1
	end
	if Input.getKey(Input.Key.Three) then
		currentSelectionMode = 2
	end

	if (timerStart - timer) <= 0 then
		if objects ~= {} then
			if not config.saves then
				config.saves = {}
			end
			config.saves["AutoSave"] = {
				objects = objects,
				folders = folders,
			}
			saveConfig()
			print("Autosaved project sucessfully")
		else
			print("dis gubby tried to save with no objects, siwwy little gub gub x3") -- slime me out for writing this please
		end
		timerStart = timer + saveTime
	end

	timer = DateTime.getCurrentTime().ticks / 10000000
	lastNKeyPress = Input.getKey(Input.Key.N)
	isGuiOpen = false
end

function onGui()
	isGuiOpen = true
	Gui.beginTabBar("Options")
	if Gui.beginTabItem("Hierarchy") then
		search = Gui.inputText("Search", search)

		if #folders == 0 and #objects == 0 then
			Gui.text("Please create a folder or new object by pressing N to get started!")
		else
			Gui.beginListBox("##ObjectList")
			for i, v: { name: string, open: boolean } in ipairs(folders) do
				local open = v.open
				local label = (open and Icon.CaretDown or Icon.CaretRight)
					.. " "
					.. (open and Icon.FolderOpen or Icon.Folder)
					.. " "
					.. v.name
					.. " ##"
					.. i

				if Gui.selectable(label, false) then
					v.open = not open
				end
				if open then
					Gui.indent()
					for j, f in ipairs(objects) do
						if f.folder == v.name and string.lower(f.name):match(string.lower(search)) ~= nil then
							if Gui.selectable(f.name .. "##" .. j, selectedObject == j) then
								selectedObject = selectedObject == j and -1 or j
							end
						end
					end
					Gui.unindent()
				end
			end

			for j, f in ipairs(objects) do
				if f.folder == "" and string.lower(f.name):match(string.lower(search)) ~= nil then
					if Gui.selectable(f.name .. "##" .. j, selectedObject == j) then
						selectedObject = selectedObject == j and -1 or j
					end
				end
			end
			Gui.endListBox()

			Gui.separator()
		end
		Gui.separatorText("Folders")
		if not inFolderCreateMode then
			if Gui.button(Icon.Folder .. " New Folder") then
				inFolderCreateMode = true
				folderView = 0
			end
			if #folders > 0 then
				Gui.sameLine()
				if Gui.button(Icon.FolderMinus .. " Delete Folder") then
					inFolderCreateMode = true
					folderView = 1
				end
			end
		else
			if folderView == 0 then
				tempFolderName = Gui.inputText("Folder Name", tempFolderName)
				if Gui.button("Confirm") then
					folders[#folders + 1] = { name = tempFolderName, open = false }
					tempFolderName = ""
					inFolderCreateMode = false
				end
				Gui.sameLine()
				if Gui.button("Cancel") then
					tempFolderName = ""
					inFolderCreateMode = false
				end
			else
				for fi, f in ipairs(folders) do
					if Gui.selectable(f.name, false) then
						table.remove(folders, fi)
						for oi, i in ipairs(objects) do
							if i.folder == f.name then
								i.folder = ""
							end
						end
						folderView = 0
						inFolderCreateMode = false
					end
					if Gui.button("Cancel") then
						folderView = 0
						inFolderCreateMode = false
					end
				end
			end
		end
		Gui.endTabItem()
	end
	if Gui.beginTabItem("Properties") then
		if selectedObject ~= -1 then
			local object = objects[selectedObject]
			if object == nil then -- you somehow selected a deleted object, how the FUCK?
				print("added logigng since this WILL cause errors later") -- it didnt somehow, but imma keep this logging for if i release it and it SOMEHOW reaches this fuckass state that i couldnt even forcefully get myself to lol
				selectedObject = -1
			end

			Gui.separatorText("Transform")
			object.transform.position = Gui.dragFloat3("Position", object.transform.position, 1, -1000000, 1000000)

			local newRot = Gui.dragFloat3("Rotation", object.transform.rotation:euler(), 0.1, -1000000, 1000000)
			object.transform.rotation = Quat.fromEuler(newRot.x, newRot.y, newRot.z)
			Gui.sameLine()
			if Gui.smallButton("Reset##Rot") then
				object.transform.rotation = Quat.identity
			end

			object.transform.scale = Gui.dragFloat3("Scale", object.transform.scale, 0.01, 0, 1000000)
			Gui.sameLine()
			if Gui.smallButton("Reset##Scale") then
				object.transform.scale = Vec3.oneVector
			end

			object.name = Gui.inputText("Name", object.name)
			if Gui.button(Icon.Copy .. "Delete Object") then
				table.remove(objects, selectedObject)
				selectedObject = -1
			end
			Gui.sameLine()
			if Gui.button(Icon.Copy .. "Duplicate Object") then
				local baseName, num = object.name:match("^(.-)%s*(%d+)$")
				local name = ""
				local numberbutnumbified = tonumber(num)
				if baseName and num and numberbutnumbified then
					name = baseName .. " " .. (numberbutnumbified + 1)
				else
					name = object.name .. " 1"
				end
				local newObj = {
					name = name,
					folder = object.folder,
					transform = Transform.new(
						object.transform.position,
						object.transform.rotation,
						object.transform.scale
					),
					colour = object.colour,
					type = object.type,
				}
				objects[#objects + 1] = newObj
				selectedObject = #objects
			end
			--Gui.sameLine()
			--if Gui.button("Reset To Default") then
			--	--object = object.baseObj
			--end
			if #folders ~= 0 then
				Gui.separatorText("Folders")
				for fi, f in ipairs(folders) do
					if Gui.selectable(f.name, f.name == object.folder) then
						if f.name == object.folder then
							object.folder = ""
						else
							object.folder = f.name
						end
					end
				end
			end

			Gui.separator()
			local quatColour = Formatting.LinearColourToQuat(object.colour)
			local quatColourBut255xed =
				Quat.new(quatColour.x * 255, quatColour.y * 255, quatColour.z * 255, quatColour.w * 255)
			local tempColour = Gui.dragFloat4("Colour", quatColourBut255xed, 1, 0, 255)

			if tempColour ~= quatColourBut255xed then
				local quatColourButUN255xed =
					Quat.new(tempColour.x / 255, tempColour.y / 255, tempColour.z / 255, tempColour.w / 255)
				object.colour = LinearColor.new(
					quatColourButUN255xed.x,
					quatColourButUN255xed.y,
					quatColourButUN255xed.z,
					quatColourButUN255xed.w
				)
			end

			Gui.beginListBox("Object Types")
			for i, objectType in objectTypes do
				if Gui.selectable(objectType.Name, object.type == objectType.TypeIndex) then
					object.type = objectType.TypeIndex
				end
			end
			Gui.endListBox()
		else
			Gui.beginDisabled()
			Gui.text("Nothing Selected")
			Gui.text("No Object Selected")
			Gui.endDisabled()
		end
		Gui.endTabItem()
	end
	if Gui.beginTabItem("Projects") then
		if inProjectMode then
			if projectView == 0 then
				if currentProjectName == "" then
					saveName = Gui.inputText("Project Name", saveName)
					if saveName == "" then
						Gui.beginDisabled()
						Gui.textDisabled("Make sure to input a name")
					end
					if Gui.button("Save " .. #objects .. " objects") then
						if not config.saves then
							config.saves = {}
						end
						config.saves[saveName] = {
							objects = objects,
							folders = folders,
						}
						saveConfig()
						currentProjectName = saveName
						saveName = ""
						inProjectMode = false
						selectedObject = -1
					end
					if saveName == "" then
						Gui.endDisabled()
					end
					if Gui.button("Cancel") then
						inProjectMode = false
						saveName = ""
					end
				else
					Gui.text("Saving...")
					if not config.saves then
						config.saves = {}
					end
					config.saves[currentProjectName] = {
						objects = objects,
						folders = folders,
					}
					saveConfig()
					inProjectMode = false
				end
			elseif projectView == 1 then
				if not config.saves then
					config.saves = {}
					saveConfig()
				end

				for n, p in config.saves do
					if Gui.selectable(n .. "##" .. n, false) then
						local tempObjects = p.objects
						for i, o in ipairs(tempObjects) do
							if o.colour == nil then
								o.colour = LinearColor.White
							else
								local redIndex = #o.colour == 3 and 0 or 4
								o.colour = LinearColor.new(o.colour[redIndex], o.colour[1], o.colour[2], o.colour[3])
							end

							if o.type == nil then
								o.type = 1
							end
						end
						objects = tempObjects
						folders = p.folders
						currentProjectName = n

						inProjectMode = false
					end
				end
				if Gui.button("Cancel") then
					inProjectMode = false
				end
			end
		else
			if currentProjectName ~= "" then
				Gui.text("Current loaded project: " .. currentProjectName)
			end
			if Gui.button("Save") then
				inProjectMode = true
				projectView = 0
			end
			Gui.sameLine()
			if Gui.button("Load") then
				inProjectMode = true
				projectView = 1
			end
			if currentProjectName ~= "" then
				Gui.sameLine()
				if Gui.button("Unload") then
					selectedObject = -1
					currentProjectName = ""
					objects = {}
					folders = {}
				end
			end
		end
		Gui.endTabItem()
	end
	if Gui.beginTabItem("Assets") then
		Gui.textDisabled("Hover over a asset and press your space bar to spawn it infront of you")
		for i, objectType in ipairs(objectTypes) do
			Gui.beginChild(objectType.Name .. "##" .. i, 115, 115, true)
			Gui.text(objectType.Name)
			Gui.endChild()
			if
				Gui.isItemHovered()
				and Input.getKey(Input.Key.SpaceBar)
				and not prevSpacebarPress
				and not objectType.PrevPress
			then
				local newObj = {
					name = "Object " .. #objects + 1,
					folder = "",
					transform = Transform.identity,
					colour = LinearColor.White,
					type = objectType.TypeIndex,
				}
				newObj.transform.position = camera.position + camera.rotation:getForwardVector() * 500
				newObj.transform.rotation = gravity.upRotation
				objects[#objects + 1] = newObj
				selectedObject = #objects
			end
			Gui.sameLine()
			objectType.PrevPress = Gui.isItemHovered() and prevSpacebarPress
		end
		prevSpacebarPress = Input.getKey(Input.Key.SpaceBar)
		Gui.newLine()
		Gui.endTabItem()
	end
	if Gui.beginTabItem("Settings") then
		Gui.separatorText("Manual Controls")
		if Gui.button("Translate") then
			currentSelectionMode = 0
		end
		Gui.sameLine()
		if Gui.button("Rotate") then
			currentSelectionMode = 1
		end
		Gui.sameLine()
		if Gui.button("Scale") then
			currentSelectionMode = 2
		end

		Gui.separatorText("Settings")
		S_hideGizmosOnUIOpen = Gui.checkbox("Hide Gizmos On UI Closed", S_hideGizmosOnUIOpen)

		Gui.separatorText("Controls")
		Gui.text("WASD - Moving the camera")
		Gui.text("N - New Cube (spawns infront of camera)")
		Gui.text("F - Set camera's focus on the select object")
		Gui.text(Icon.Backspace .. " - Delete selected object")
		Gui.text("1 - Change gizmo to Translate")
		Gui.text("2 - Change gizmo to Rotate")
		Gui.text("3 - Change gizmo to Scale")
		Gui.separatorText("Debug stuff?")
		Gui.text("Autosave timer: " .. tostring(timerStart - timer))
		Gui.text("Is GUI Open: " .. tostring(isGuiOpen))

		Gui.endTabItem()
	end
	Gui.endTabBar()
	isGuiOpen = true
end
