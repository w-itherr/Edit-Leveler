--!strict

--[[
	Hello fellow code reader! Please be aware all of this code is really messy but here is a few key things that if you are looking for, hopefully this can help :]
	Everything is split into their own files and the names are a bit confusing but they should be descriptive of what they do!

	/Editor.luau - This is the file you are in but this brings everything together

	/Drawing/DrawingHelper.luau - This is just a simple little library I use here and there for drawing stuff (Faces, Polygons and Circles)
	/Drawing/ObjectDrawer.luau - This handles everything to do with everything you see on the screen such as; the objects being drawn and the gizmos being drawn
	/Librarys/Controlling.luau - This handles everything to do with all the gizmos and all the math that this project took just for it to be in a good enough state to release
	/Librarys/Freecam.luau - This controls how you move and rotate the camera, taken this code from the anotheraxiom.freecam script and modified to have the features I needed
		
	If you see anything that you think should be changed via code, feel free to tell me in the thread! Just dont be rude about it please :]
	Also everything here was made over a few months of me working on this and then not at really late into the night, so everything WILL be messy lol
]]

local ObjectDrawer = require("Drawing/objectDrawer")
local Gltf = require("Drawing/gltf")
local Freecam = require("Librarys/freecam")
local Controlling = require("Librarys/controlling")

-- Types
type Asset = {
	name: string,
	path: string,
}

type Object = {
	name: string,
	transform: Transform,
	folder: string,
	meshPath: string,
}

type Folder = {
	name: string,
	open: boolean,
}

type LoadedObject = {
	Object: Object,
	LuauMesh: LuauMesh,
}

type ProjectObject = {
	name: string,
	transform: Transform,
	folder: string,
	meshPath: string,
	colour: LinearColor | {},
}

type EditProject = {
	LoadedObjects: { ProjectObject },
}

local Assets: { Asset } = {}
local LoadedObjects: { LoadedObject } = {}
local Folders: { Folder } = {}

-- object stuff
local selectedObject = -1
local search = ""
local currentSelectionMode = 0 -- 0 = Translation, 1 = Rotation, 2 = Scale

-- Inputs
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

function GetAssets()
	Assets = {}
	for i, fileName in ipairs(LuauFile.listFiles("Objects")) do
		local lower = fileName:lower()
		print(lower)
		if lower:match("%.glb$") or lower:match("%.gltf$") then
			print(lower)
			local asset = {
				path = lower,
				name = fileName:split("/")[#fileName:split("/")]:split(".")[1],
			}
			table.insert(Assets, asset)
		end
	end
end

function onTransitionBegin(transitionInfo: Transition)
	camera.positionSmoothing = 0.02
	camera.rotationSmoothing = 0.02
	camera.fieldOfViewSmoothing = 0.05
	transitionInfo.length = 0
	postProcessSettings.depthOfFieldFocalDistance = 0
	camera.fieldOfView = 70

	local gamemodes: { string } = SpectatorGamemodes.listGamemodeIds()

	if #gamemodes == 0 then -- assume this is shuttle
		camera.position = Vec3.new(1325.000, 15.000, 84.000)
		camera.rotation = Quat.fromEuler(0, -5.000, -53)
		Freecam.setRotAndGrav(Vec3.new(0, -5, -53), Quat.fromEuler(0, 0, 0))
	else
		for i, gamemode in ipairs(gamemodes) do
			if gamemode:find("scraprun") or gamemode:find("TKB_") then -- assume this orion
				camera.position = Vec3.new(25000.000, 2850.000, 13790.00)
				camera.rotation = Quat.fromEuler(0, 0, 90)
				Freecam.setRotAndGrav(Vec3.new(0, 0, 90), Quat.fromEuler(0, 90, 0))
				break
			elseif gamemode:find("Gamma 0") or gamemode:find("Beta 0") or gamemode:find("Alpha 0") then -- assume this is ares lol
				camera.position = Vec3.new(-474.586, -7617.812, 237.312)
				camera.rotation = Quat.fromEuler(0, -7.553, -61.674)
				Freecam.setRotAndGrav(Vec3.new(0, -7.553, -61.674), Quat.fromEuler(0, 0, 0))
				break
			end
		end
	end

	timer = DateTime.getCurrentTime().ticks / 10000000
	timerStart = timer + saveTime
	GetAssets()

	Folders = {}
	LoadedObjects = {}
	selectedObject = -1

	WorldDraw.clearAll()
end

function RedrawAll()
	WorldDraw.clear()

	for i, object in ipairs(LoadedObjects) do
		object.LuauMesh.position = object.Object.transform.position
		object.LuauMesh.rotation = object.Object.transform.rotation
		local newScale = object.Object.transform.scale * 100

		if newScale.x == 0 then -- this has to be done as when luaumesh's are scale to 0 they just go invis and that isnt really the functionality i would like
			newScale.x = 0.0001
		end
		if newScale.y == 0 then
			newScale.y = 0.0001
		end
		if newScale.z == 0 then
			newScale.z = 0.0001
		end

		object.LuauMesh.scale = newScale

		object.LuauMesh:draw()
	end

	if selectedObject ~= -1 then
		local object = LoadedObjects[selectedObject]
		local drawIt = true
		if S_hideGizmosOnUIOpen and not isGuiOpen then
			drawIt = false
		end

		if drawIt then
			ObjectDrawer.DrawGizmos(object.Object.transform, currentSelectionMode)
		end
	end
	--end
end

function SpawnMesh(objectPath: string, objectName: string, objectTransform: Transform) -- yoinked from aa.modelviewer and slightly modified to use what i need to use :]
	local baseDir = objectPath:match("^(.*)/[^/]+$") or ""

	local ok, vertices, triangles, normals, uvs, _textures
	if objectPath:lower():match("%.glb$") then
		local bytes = LuauFile.loadBytes(objectPath)
		if #bytes == 0 then
			print("Failed to read " .. objectPath .. " defaulting to cube.")
			if objectName ~= "objects/cube.glb" then
				SpawnMesh("objects/cube.glb", objectName, objectTransform)
			else
				print(
					"bro why are you even using edit leveler without a cube, but fine i'll default to the FIRST object you have saved..."
				)
				SpawnMesh(Assets[0].path, objectName, objectTransform)
			end
			return
		end
		ok, vertices, triangles, normals, uvs, _textures = pcall(Gltf.parseGlb, bytes, baseDir)
	else
		local text = LuauFile.loadText(objectPath)
		if text == "" then
			print("Failed to read " .. objectPath)
			return
		end
		ok, vertices, triangles, normals, uvs, _textures = pcall(Gltf.parse, text, baseDir)
	end
	if not ok then
		-- on pcall failure the second value is the error message
		print("Failed to parse " .. objectPath .. ": " .. tostring(vertices))
		return
	end

	local mesh = WorldDraw.spawnMesh()
	if mesh == nil then
		print("Failed to spawn a mesh")
		return
	end
	mesh.position = camera.position
	mesh.rotation = Quat.identity
	-- glTF units are meters, world units are cm
	mesh.scale = Vec3.new(100, 100, 100)
	mesh.vertices = vertices
	mesh.triangles = triangles
	mesh.normals = normals
	mesh.uVs = uvs
	mesh:draw()

	local ObjectObject: Object = {
		name = objectName,
		transform = objectTransform,
		folder = "",
		meshPath = objectPath,
	}

	local NewObject: LoadedObject = {
		Object = ObjectObject,
		LuauMesh = mesh,
	}

	table.insert(LoadedObjects, NewObject)
end

function DoGizmoControlling()
	if selectedObject ~= -1 then
		local object = LoadedObjects[selectedObject]
		if currentSelectionMode == 0 then
			rotateCam = Controlling.ControlTranslateGizmo(object.Object)
		elseif currentSelectionMode == 1 then
			rotateCam = Controlling.ControlRotateGizmo(object.Object)
		elseif currentSelectionMode == 2 then
			rotateCam = Controlling.ControlScaleGizmo(object.Object)
		end
	end
end

function SaveProject(projectName: string): boolean
	if not config.saves then
		config.saves = {}
	end

	local ProjectsObjects: { ProjectObject } = {}

	for i, object: LoadedObject in LoadedObjects do
		ProjectsObjects[i] = {
			name = object.Object.name,
			transform = object.Object.transform,
			folder = object.Object.folder,
			meshPath = object.Object.meshPath,
			colour = object.LuauMesh.color,
		}
	end

	local Project: EditProject = {
		LoadedObjects = ProjectsObjects,
	}

	config.saves[projectName] = Project

	saveConfig()
	return true
end

function LoadProject(projectName: string): boolean
	if not config.saves then
		config.saves = {}
		return false
	end

	if not config.saves[projectName] then
		return false
	end

	local project = config.saves[projectName]

	if project["objects"] then
		print("Old project format, moving to a seperate json and not loading.") -- ig add a way to load old projects but it'd be way better to just not load em atm

		if not config.oldSaves then
			config.oldSaves = {}
		end

		if config.oldSaves[projectName] then
			config.saves[projectName] = nil

			return false -- already in old saves
		end

		config.oldSaves[projectName] = project
		config.saves[projectName] = nil
		saveConfig()
		return false
	end

	for i, object: LoadedObject in ipairs(LoadedObjects) do
		object.LuauMesh:destroy()
	end
	LoadedObjects = {}
	Folders = {}

	for i, object: ProjectObject in ipairs(project["LoadedObjects"]) do
		SpawnMesh(object.meshPath, object.name, object.transform)
		local newObject = LoadedObjects[#LoadedObjects]

		local colour = object.colour :: { number }
		local redIndex = #colour == 3 and 0 or 4
		newObject.LuauMesh.color = LinearColor.new(colour[redIndex], colour[1], colour[2], colour[3])

		newObject.Object.folder = object.folder

		local doesFolderExist = false

		for i, folder: Folder in Folders do
			if folder.name == object.folder then
				doesFolderExist = true
			end
		end

		if not doesFolderExist and object.folder ~= "" then
			Folders[#Folders + 1] = { name = object.folder, open = false }
		end
	end

	return true
end

function tick(dt)
	RedrawAll()
	if not (S_hideGizmosOnUIOpen and not isGuiOpen) then
		DoGizmoControlling()
		Freecam.frecamtick(dt, rotateCam)
	else
		Freecam.frecamtick(dt, true)
	end

	if Input.getKey(Input.Key.F) and selectedObject ~= -1 then
		camera.position = LoadedObjects[selectedObject].Object.transform.position
			+ LoadedObjects[selectedObject].Object.transform.rotation:getForwardVector() * -250
			+ LoadedObjects[selectedObject].Object.transform.rotation:getUpVector() * 250
			+ LoadedObjects[selectedObject].Object.transform.rotation:getRightVector() * -250
		camera:lookAt(
			LoadedObjects[selectedObject].Object.transform.position,
			LoadedObjects[selectedObject].Object.transform.rotation:getUpVector()
		)

		Freecam.setRotAndGrav(camera.rotation:euler(), LoadedObjects[selectedObject].Object.transform.rotation)
	end

	if (Input.getKey(Input.Key.BackSpace) or Input.getKey(Input.Key.Delete)) and selectedObject ~= -1 then
		LoadedObjects[selectedObject].LuauMesh:destroy()
		table.remove(LoadedObjects, selectedObject)
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
		if LoadedObjects ~= {} then
			if not config.saves then
				config.saves = {}
			end
			SaveProject("AutoSave")
			saveConfig()
			print("Autosaved project sucessfully")
		else
			print("autosave failed, no objects loaded")
		end
		timerStart = timer + saveTime
	end

	timer = DateTime.getCurrentTime().ticks / 10000000
	isGuiOpen = false
end

function onGui()
	isGuiOpen = true

	Gui.beginTabBar("Options")
	if Gui.beginTabItem("Hierarchy") then
		search = Gui.inputText("Search", search)

		if #Folders == 0 and #LoadedObjects == 0 then
			Gui.text("Nothing loaded, get started by going into the Assets tab!")
		else
			Gui.beginListBox("##ObjectList")
			for i, v: Folder in ipairs(Folders) do
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
					for j, f: LoadedObject in ipairs(LoadedObjects) do
						if
							f.Object.folder == v.name
							and string.lower(f.Object.name):match(string.lower(search)) ~= nil
						then
							if Gui.selectable(f.Object.name .. "##" .. j, selectedObject == j) then
								selectedObject = selectedObject == j and -1 or j
							end
						end
					end
					Gui.unindent()
				end
			end

			for j, f in ipairs(LoadedObjects) do
				if f.Object.folder == "" and string.lower(f.Object.name):match(string.lower(search)) ~= nil then
					if Gui.selectable(f.Object.name .. "##" .. j, selectedObject == j) then
						selectedObject = selectedObject == j and -1 or j
					end
				end
			end
			Gui.endListBox()

			Gui.separator()
		end

		if #LoadedObjects == 0 then
			Gui.beginDisabled()
		end

		Gui.separatorText("Folders")
		if not inFolderCreateMode then
			if Gui.button(Icon.Folder .. " New Folder") then
				inFolderCreateMode = true
				folderView = 0
			end
			if #Folders > 0 then
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
					Folders[#Folders + 1] = { name = tempFolderName, open = false }
					tempFolderName = ""
					inFolderCreateMode = false
				end
				Gui.sameLine()
				if Gui.button("Cancel") then
					tempFolderName = ""
					inFolderCreateMode = false
				end
			else
				for fi, f in ipairs(Folders) do
					if Gui.selectable(f.name, false) then
						table.remove(Folders, fi)
						for oi, i in ipairs(LoadedObjects) do
							if i.Object.folder == f.name then
								i.Object.folder = ""
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
		if #LoadedObjects == 0 then
			Gui.endDisabled()
		end

		Gui.endTabItem()
	end
	if Gui.beginTabItem("Properties") then
		if selectedObject ~= -1 then
			local object = LoadedObjects[selectedObject].Object
			local luauMesh = LoadedObjects[selectedObject].LuauMesh
			if object == nil then -- you somehow selected a deleted object, how the freak?
				print("added logigng since this WILL cause errors later") -- it didnt somehow, but imma keep this logging for if i release it and it SOMEHOW reaches this stupid state that i couldnt even forcefully get myself to lol
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
				LoadedObjects[selectedObject].LuauMesh:destroy()
				table.remove(LoadedObjects, selectedObject)
				selectedObject = -1
			end
			if #Folders ~= 0 then
				Gui.separatorText("Folders")
				for fi, f in ipairs(Folders) do
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
			local newColour = Gui.colorEdit("Colour", luauMesh.color)
			if newColour ~= luauMesh.color then
				luauMesh.color = newColour
				luauMesh:draw()
			end
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
						Gui.textColored(LinearColor.new(1, 0, 0, 1), "Make sure to input a name")
					elseif config.saves[saveName] ~= nil then
						Gui.beginDisabled()
						Gui.textColored(
							LinearColor.new(1, 0, 0, 1),
							"You cannot make a project with the same name as another project."
						)
					end
					if Gui.button("Save " .. #LoadedObjects .. " objects") then
						SaveProject(saveName)

						currentProjectName = saveName
						saveName = ""
						inProjectMode = false
						selectedObject = -1
					end
					if saveName == "" or config.saves[saveName] ~= nil then
						Gui.endDisabled()
					end
					if Gui.button("Cancel") then
						inProjectMode = false
						saveName = ""
					end
				else
					Gui.text("Saving...")
					SaveProject(currentProjectName)
					saveConfig()
					inProjectMode = false
				end
			elseif projectView == 1 then
				if not config.saves then
					config.saves = {}
					saveConfig()
				end

				for n, p in config.saves do
					if Gui.selectable(p .. "##" .. n, false) then
						if LoadProject(n) then
							currentProjectName = n
						end
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
					for i, object in ipairs(LoadedObjects) do
						object.LuauMesh:destroy()
					end

					LoadedObjects = {}
					Folders = {}

					selectedObject = -1
					currentProjectName = ""
				end
			end
		end
		Gui.endTabItem()
	end
	if Gui.beginTabItem("Assets") then
		Gui.textDisabled("Hover over a asset and press your space bar to spawn it infront of you")
		for i, assetType in ipairs(Assets) do
			Gui.beginChild(assetType.name .. "##" .. i, 115, 115, true)
			Gui.text(assetType.name)
			Gui.endChild()
			if Gui.isItemHovered() and Input.getKey(Input.Key.SpaceBar) and not prevSpacebarPress then
				SpawnMesh(
					assetType.path,
					"Object " .. #LoadedObjects + 1,
					Transform.new(
						camera.position + camera.rotation:getForwardVector() * 500,
						gravity.upRotation,
						Vec3.oneVector
					)
				)
				selectedObject = #LoadedObjects
			end
			if i % 4 ~= 0 then
				Gui.sameLine()
			end
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
		Gui.text("F - Set camera's focus on the select object")
		Gui.text(Icon.Backspace .. " or DEL - Delete selected object")
		Gui.text("1 - Change gizmo to Translate")
		Gui.text("2 - Change gizmo to Rotate")
		Gui.text("3 - Change gizmo to Scale")
		--[[Gui.separatorText("Debug stuff?")
		Gui.text("Autosave timer: " .. tostring(timerStart - timer))
		Gui.text("Is GUI Open: " .. tostring(isGuiOpen)) -- why is this here when all the time i should see it? idk. do i want more stuff to make debug stuff look nerdy? ya!
		--]]
		Gui.endTabItem()
	end
	Gui.endTabBar()
	isGuiOpen = true
end
