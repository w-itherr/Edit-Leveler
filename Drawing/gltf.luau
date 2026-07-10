--!strict
-- glTF 2.0 loader for LuauMesh. Handles .gltf (embedded or external .bin
-- buffers) and .glb. External buffers/images load through LuauFile relative
-- to baseDir, so they have to live inside the camera package.

-- Yoinked from aa.modelviewer

local Gltf = {}

-- base64 -> table of bytes (1-indexed, each 0..255)

local BASE64_LOOKUP: { [string]: number } = {}
do
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #chars do
		BASE64_LOOKUP[string.sub(chars, i, i)] = i - 1
	end
end

local function base64Decode(s: string): { number }
	-- strip whitespace and '=' padding; the trimmed length tells us how many
	-- output bytes to emit
	s = string.gsub(s, "[^A-Za-z0-9%+/]", "")

	local bytes: { number } = {}
	local n = #s
	local i = 1
	while i <= n do
		local c1 = BASE64_LOOKUP[string.sub(s, i, i)] or 0
		local c2 = BASE64_LOOKUP[string.sub(s, i + 1, i + 1)] or 0
		local c3 = BASE64_LOOKUP[string.sub(s, i + 2, i + 2)] or 0
		local c4 = BASE64_LOOKUP[string.sub(s, i + 3, i + 3)] or 0
		local combined = bit32.bor(bit32.lshift(c1, 18), bit32.lshift(c2, 12), bit32.lshift(c3, 6), c4)
		table.insert(bytes, bit32.band(bit32.rshift(combined, 16), 0xFF))
		if i + 2 <= n then
			table.insert(bytes, bit32.band(bit32.rshift(combined, 8), 0xFF))
		end
		if i + 3 <= n then
			table.insert(bytes, bit32.band(combined, 0xFF))
		end
		i = i + 4
	end
	return bytes
end

-- URIs are relative to the source file and may be percent-encoded
-- ("My%20Model.bin")
local function decodeUri(uri: string): string
	return (uri:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16) :: number)
	end))
end

local function resolveUri(baseDir: string, uri: string): string
	local decoded = decodeUri(uri)
	if baseDir == "" then
		return decoded
	end
	return baseDir .. "/" .. decoded
end

-- data URIs decode inline, external .bin files load from disk, and a buffer
-- with no URI is backed by the .glb BIN chunk
local function loadBuffers(gltf: any, binChunk: { number }?, baseDir: string): { { number } }
	local buffers: { { number } } = {}
	if not gltf.buffers then
		return buffers
	end
	for i, buffer in ipairs(gltf.buffers) do
		if type(buffer.uri) == "string" then
			if string.sub(buffer.uri, 1, 5) == "data:" then
				local b64 = string.match(buffer.uri, "base64,(.+)$")
				if not b64 then
					error("gltf: buffer " .. (i - 1) .. " data URI is not base64")
				end
				buffers[i] = base64Decode(b64)
			else
				local path = resolveUri(baseDir, buffer.uri)
				local bytes = LuauFile.loadBytes(path)
				if #bytes == 0 then
					error(
						"gltf: failed to read external buffer '" .. path .. "' -- it must sit inside the camera package"
					)
				end
				buffers[i] = bytes
			end
		elseif binChunk ~= nil then
			buffers[i] = binChunk
		else
			error("gltf: buffer " .. (i - 1) .. " has no URI and no .glb BIN chunk")
		end
	end
	return buffers
end

-- little-endian readers. offset is 1-based to match Luau string indexing

local function readUint16LE(bytes: { number }, offset: number): number
	return bit32.bor(bytes[offset], bit32.lshift(bytes[offset + 1], 8))
end

local function readUint32LE(bytes: { number }, offset: number): number
	return bit32.bor(
		bytes[offset],
		bit32.lshift(bytes[offset + 1], 8),
		bit32.lshift(bytes[offset + 2], 16),
		bit32.lshift(bytes[offset + 3], 24)
	)
end

-- IEEE 754 float32 by hand, since all we have is a byte table
local function readFloat32LE(bytes: { number }, offset: number): number
	local b0 = bytes[offset]
	local b1 = bytes[offset + 1]
	local b2 = bytes[offset + 2]
	local b3 = bytes[offset + 3]

	local sign = bit32.rshift(b3, 7)
	local exponent = bit32.bor(bit32.lshift(bit32.band(b3, 0x7F), 1), bit32.rshift(b2, 7))
	local mantissa = bit32.bor(bit32.lshift(bit32.band(b2, 0x7F), 16), bit32.lshift(b1, 8), b0)

	if exponent == 0 then
		if mantissa == 0 then
			return sign == 1 and -0 or 0
		end
		-- subnormal
		local value = mantissa / 2 ^ 23 * 2 ^ -126
		return sign == 1 and -value or value
	elseif exponent == 0xFF then
		if mantissa == 0 then
			return sign == 1 and -math.huge or math.huge
		end
		return 0 / 0 -- NaN
	end

	local value = (1 + mantissa / 2 ^ 23) * 2 ^ (exponent - 127)
	return sign == 1 and -value or value
end

-- the glTF componentType values we care about
local COMP_UNSIGNED_SHORT = 5123
local COMP_UNSIGNED_INT = 5125
local COMP_FLOAT = 5126

-- 4x4 matrices as flat 16-element column-major tables (index = col * 4 + row
-- + 1). That's the spec's layout too, so node.matrix copies straight in.

local function matIdentity(): { number }
	return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
end

local function matMul(a: { number }, b: { number }): { number }
	local out: { number } = {}
	for col = 0, 3 do
		for row = 0, 3 do
			local sum = 0
			for k = 0, 3 do
				sum = sum + a[k * 4 + row + 1] * b[col * 4 + k + 1]
			end
			out[col * 4 + row + 1] = sum
		end
	end
	return out
end

-- M = T * R * S from a node's optional translation / rotation (quat x,y,z,w)
-- / scale
local function matFromTRS(t: { number }?, r: { number }?, s: { number }?): { number }
	local tx, ty, tz = 0, 0, 0
	if t then
		tx, ty, tz = t[1] or 0, t[2] or 0, t[3] or 0
	end
	local qx, qy, qz, qw = 0, 0, 0, 1
	if r then
		qx, qy, qz, qw = r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 1
	end
	local sx, sy, sz = 1, 1, 1
	if s then
		sx, sy, sz = s[1] or 1, s[2] or 1, s[3] or 1
	end

	-- quaternion -> rotation matrix
	local xx, yy, zz = qx * qx, qy * qy, qz * qz
	local xy, xz, yz = qx * qy, qx * qz, qy * qz
	local wx, wy, wz = qw * qx, qw * qy, qw * qz

	local r00 = 1 - 2 * (yy + zz)
	local r01 = 2 * (xy - wz)
	local r02 = 2 * (xz + wy)
	local r10 = 2 * (xy + wz)
	local r11 = 1 - 2 * (xx + zz)
	local r12 = 2 * (yz - wx)
	local r20 = 2 * (xz - wy)
	local r21 = 2 * (yz + wx)
	local r22 = 1 - 2 * (xx + yy)

	-- columns of R scaled by sx/sy/sz, translation in the last column
	return {
		r00 * sx,
		r10 * sx,
		r20 * sx,
		0,
		r01 * sy,
		r11 * sy,
		r21 * sy,
		0,
		r02 * sz,
		r12 * sz,
		r22 * sz,
		0,
		tx,
		ty,
		tz,
		1,
	}
end

local function matTransformPoint(m: { number }, x: number, y: number, z: number): (number, number, number)
	return m[1] * x + m[5] * y + m[9] * z + m[13],
		m[2] * x + m[6] * y + m[10] * z + m[14],
		m[3] * x + m[7] * y + m[11] * z + m[15]
end

-- upper-left 3x3 only. Non-uniform scale would strictly need the
-- inverse-transpose, but Blender exports are almost always uniform.
local function matTransformDirection(m: { number }, x: number, y: number, z: number): (number, number, number)
	local nx = m[1] * x + m[5] * y + m[9] * z
	local ny = m[2] * x + m[6] * y + m[10] * z
	local nz = m[3] * x + m[7] * y + m[11] * z
	local len = math.sqrt(nx * nx + ny * ny + nz * nz)
	if len == 0 then
		return 0, 0, 0
	end
	return nx / len, ny / len, nz / len
end

local function nodeLocalTransform(node: any): { number }
	if node.matrix then
		local m: { number } = {}
		for i = 1, 16 do
			m[i] = node.matrix[i] or 0
		end
		return m
	end
	return matFromTRS(node.translation, node.rotation, node.scale)
end

-- walk the scene graph collecting (mesh, world transform) for every node
-- that references a mesh
local function collectMeshNodes(
	gltf: any,
	nodeIndices: { number },
	parent: { number },
	out: { { mesh: number, transform: { number } } }
)
	if not nodeIndices then
		return
	end
	for _, nodeIndex in ipairs(nodeIndices) do
		local node = gltf.nodes and gltf.nodes[nodeIndex + 1]
		if node then
			local world = matMul(parent, nodeLocalTransform(node))
			if node.mesh ~= nil then
				table.insert(out, { mesh = node.mesh, transform = world })
			end
			if node.children then
				collectMeshNodes(gltf, node.children, world, out)
			end
		end
	end
end

-- reads one primitive, applies the world transform, appends to the running
-- arrays. normalsPresent/uvsPresent flip to false when a primitive lacks the
-- attribute -- a partial array would fail the length check on the C++ side.
local function extractPrimitive(
	gltf: any,
	buffers: { { number } },
	prim: any,
	transform: { number },
	allVertices: { Vec3 },
	allTriangles: { number },
	allNormals: { Vec3 },
	allUvs: { Vec2 },
	normalsPresent: { boolean },
	uvsPresent: { boolean }
)
	local accessors = gltf.accessors
	local views = gltf.bufferViews

	local function getAttrView(attrIndex: number?): (any?, any?)
		if attrIndex == nil then
			return nil, nil
		end
		local acc = accessors[attrIndex + 1]
		local view = views[acc.bufferView + 1]
		return acc, view
	end

	local posAcc, posView = getAttrView(prim.attributes and prim.attributes.POSITION)
	if not posAcc then
		error("gltf: primitive has no POSITION attribute")
	end
	local norAcc, norView = getAttrView(prim.attributes and prim.attributes.NORMAL)
	local uvAcc, uvView = getAttrView(prim.attributes and prim.attributes.TEXCOORD_0)
	local idxAcc, idxView = getAttrView(prim.indices)
	if not idxAcc then
		error("gltf: non-indexed primitives aren't supported")
	end

	if posAcc.componentType ~= COMP_FLOAT or posAcc.type ~= "VEC3" then
		error("gltf: POSITION must be VEC3 floats")
	end

	local function viewStart(acc: any, view: any): number
		local viewOffset = (view.byteOffset or 0)
		local accOffset = (acc.byteOffset or 0)
		return viewOffset + accOffset + 1
	end

	local function viewBytes(view: any): { number }
		local b = buffers[(view.buffer or 0) + 1]
		if not b then
			error("gltf: bufferView references missing buffer " .. tostring(view.buffer))
		end
		return b
	end

	-- new vertices start here in the merged array
	local vertexOffset = #allVertices

	-- positions. byteStride overrides the packed element size when the buffer
	-- is interleaved
	do
		local bytes = viewBytes(posView)
		local base = viewStart(posAcc, posView)
		local stride = posView.byteStride or 12
		for i = 0, posAcc.count - 1 do
			local o = base + i * stride
			local x, y, z = readFloat32LE(bytes, o), readFloat32LE(bytes, o + 4), readFloat32LE(bytes, o + 8)
			x, y, z = matTransformPoint(transform, x, y, z)
			table.insert(allVertices, Vec3.new(x, y, z))
		end
	end

	-- normals: rotate and renormalize
	if norAcc and norAcc.componentType == COMP_FLOAT and norAcc.type == "VEC3" then
		local bytes = viewBytes(norView)
		local base = viewStart(norAcc, norView)
		local stride = norView.byteStride or 12
		for i = 0, norAcc.count - 1 do
			local o = base + i * stride
			local x, y, z = readFloat32LE(bytes, o), readFloat32LE(bytes, o + 4), readFloat32LE(bytes, o + 8)
			x, y, z = matTransformDirection(transform, x, y, z)
			table.insert(allNormals, Vec3.new(x, y, z))
		end
	else
		normalsPresent[1] = false
	end

	-- UVs. No V flip here -- that's an OBJ-ism, glTF is top-left like Unreal
	if uvAcc and uvAcc.componentType == COMP_FLOAT and uvAcc.type == "VEC2" then
		local bytes = viewBytes(uvView)
		local base = viewStart(uvAcc, uvView)
		local stride = uvView.byteStride or 8
		for i = 0, uvAcc.count - 1 do
			local o = base + i * stride
			table.insert(allUvs, Vec2.new(readFloat32LE(bytes, o), readFloat32LE(bytes, o + 4)))
		end
	else
		uvsPresent[1] = false
	end

	-- indices, winding swapped (a, c, b) for Unreal
	if idxAcc.type ~= "SCALAR" then
		error("gltf: indices accessor must be SCALAR")
	end
	local idxStride: number
	local idxReader: ({ number }, number) -> number
	if idxAcc.componentType == COMP_UNSIGNED_SHORT then
		idxStride = 2
		idxReader = readUint16LE
	elseif idxAcc.componentType == COMP_UNSIGNED_INT then
		idxStride = 4
		idxReader = readUint32LE
	else
		error("gltf: unsupported index componentType " .. tostring(idxAcc.componentType))
	end
	if idxAcc.count % 3 ~= 0 then
		error("gltf: index count " .. tostring(idxAcc.count) .. " is not a multiple of 3")
	end
	local idxBytes = viewBytes(idxView)
	local idxBase = viewStart(idxAcc, idxView)
	for tri = 0, idxAcc.count - 1, 3 do
		local o = idxBase + tri * idxStride
		local a = idxReader(idxBytes, o) + vertexOffset
		local b = idxReader(idxBytes, o + idxStride) + vertexOffset
		local c = idxReader(idxBytes, o + idxStride * 2) + vertexOffset
		table.insert(allTriangles, a)
		table.insert(allTriangles, c)
		table.insert(allTriangles, b)
	end
end

-- image bytes can come from a data URI, an external file, or a bufferView
-- slice into the binary chunk
local function extractImageBytes(gltf: any, buffers: { { number } }, baseDir: string, imageIndex: number): { number }?
	local image = gltf.images and gltf.images[imageIndex + 1]
	if not image then
		return nil
	end

	if type(image.uri) == "string" then
		if string.sub(image.uri, 1, 5) == "data:" then
			local b64 = string.match(image.uri, "base64,(.+)$")
			if b64 then
				return base64Decode(b64)
			end
			return nil
		end
		local bytes = LuauFile.loadBytes(resolveUri(baseDir, image.uri))
		if #bytes == 0 then
			return nil
		end
		return bytes
	end

	if image.bufferView ~= nil then
		local view = gltf.bufferViews[image.bufferView + 1]
		if not view then
			return nil
		end
		local bufferBytes = buffers[(view.buffer or 0) + 1]
		if not bufferBytes then
			return nil
		end
		local startIdx = (view.byteOffset or 0) + 1
		local length = view.byteLength or 0
		if length <= 0 then
			return nil
		end
		local out: { number } = {}
		for i = 0, length - 1 do
			out[i + 1] = bufferBytes[startIdx + i]
		end
		return out
	end

	return nil
end

-- first material wins since LuauMesh only has one material slot. Returns raw
-- image bytes for baseColor / normal / metallicRoughness (G = roughness,
-- B = metallic) / occlusion.
local function findMaterialTextures(gltf: any, buffers: { { number } }, baseDir: string): { [string]: { number } }
	local out: { [string]: { number } } = {}
	if not gltf.meshes or not gltf.materials or not gltf.textures then
		return out
	end

	local function grab(slot: string, textureInfo: any)
		if textureInfo == nil or textureInfo.index == nil then
			return
		end
		local texture = gltf.textures[textureInfo.index + 1]
		if texture and texture.source ~= nil then
			local imgBytes = extractImageBytes(gltf, buffers, baseDir, texture.source)
			if imgBytes and #imgBytes > 0 then
				out[slot] = imgBytes
			end
		end
	end

	for _, mesh in ipairs(gltf.meshes) do
		if mesh.primitives then
			for _, prim in ipairs(mesh.primitives) do
				if prim.material ~= nil then
					local material = gltf.materials[prim.material + 1]
					if material then
						local pbr = material.pbrMetallicRoughness
						if pbr then
							grab("baseColor", pbr.baseColorTexture)
							grab("metallicRoughness", pbr.metallicRoughnessTexture)
						end
						grab("normal", material.normalTexture)
						grab("occlusion", material.occlusionTexture)
						return out
					end
				end
			end
		end
	end
	return out
end

local function buildMesh(
	gltf: any,
	buffers: { { number } },
	baseDir: string
): ({ Vec3 }, { number }, { Vec3 }, { Vec2 }, { [string]: { number } })
	if not gltf.accessors or not gltf.bufferViews then
		error("gltf: file is missing accessors or bufferViews")
	end
	if not gltf.meshes or #gltf.meshes == 0 then
		error("gltf: file has no meshes")
	end

	local meshNodes: { { mesh: number, transform: { number } } } = {}
	if gltf.scenes and gltf.nodes then
		local sceneIdx = (gltf.scene or 0) + 1
		local scene = gltf.scenes[sceneIdx]
		if scene and scene.nodes then
			collectMeshNodes(gltf, scene.nodes, matIdentity(), meshNodes)
		end
	end
	-- no scene/nodes section: just render every mesh at the origin
	if #meshNodes == 0 then
		for i = 0, #gltf.meshes - 1 do
			table.insert(meshNodes, { mesh = i, transform = matIdentity() })
		end
	end

	local allVertices: { Vec3 } = {}
	local allTriangles: { number } = {}
	local allNormals: { Vec3 } = {}
	local allUvs: { Vec2 } = {}
	local normalsPresent = { true }
	local uvsPresent = { true }

	for _, meshNode in ipairs(meshNodes) do
		local mesh = gltf.meshes[meshNode.mesh + 1]
		if mesh and mesh.primitives then
			for _, prim in ipairs(mesh.primitives) do
				extractPrimitive(
					gltf,
					buffers,
					prim,
					meshNode.transform,
					allVertices,
					allTriangles,
					allNormals,
					allUvs,
					normalsPresent,
					uvsPresent
				)
			end
		end
	end

	if #allVertices == 0 then
		error("gltf: file has no renderable primitives")
	end

	-- if any primitive was missing normals or UVs, drop the whole attribute
	-- and let the C++ side fill in defaults
	if not normalsPresent[1] then
		allNormals = {}
	end
	if not uvsPresent[1] then
		allUvs = {}
	end

	local textures = findMaterialTextures(gltf, buffers, baseDir)

	return allVertices, allTriangles, allNormals, allUvs, textures
end

-- .gltf (text). jsonText is the contents of LuauFile.loadText, baseDir is
-- the file's package-relative folder ("" or nil at the package root) so
-- external .bin buffers and images resolve.
function Gltf.parse(
	jsonText: string,
	baseDir: string?
): ({ Vec3 }, { number }, { Vec3 }, { Vec2 }, { [string]: { number } })
	local gltf = LuauJson.parse(jsonText)
	if gltf == nil then
		error("gltf: file is not valid JSON")
	end
	if type(gltf) ~= "table" then
		error("gltf: top-level value is not an object")
	end
	if not gltf.buffers or not gltf.buffers[1] then
		error("gltf: file has no buffers")
	end

	local buffers = loadBuffers(gltf, nil, baseDir or "")
	return buildMesh(gltf, buffers, baseDir or "")
end

-- .glb (binary): 12-byte header (magic "glTF", uint32 version, uint32 total
-- length) followed by JSON and BIN chunks. bytes is the contents of
-- LuauFile.loadBytes.
function Gltf.parseGlb(
	bytes: { number },
	baseDir: string?
): ({ Vec3 }, { number }, { Vec3 }, { Vec2 }, { [string]: { number } })
	if #bytes < 12 then
		error("gltf: file too small to be a .glb")
	end

	if bytes[1] ~= 0x67 or bytes[2] ~= 0x6C or bytes[3] ~= 0x54 or bytes[4] ~= 0x46 then -- "glTF"
		error("gltf: not a .glb file")
	end

	local version = readUint32LE(bytes, 5)
	if version ~= 2 then
		error("gltf: unsupported .glb version " .. tostring(version))
	end

	local totalLength = readUint32LE(bytes, 9)
	if totalLength > #bytes then
		error(
			"gltf: .glb truncated (header says "
				.. tostring(totalLength)
				.. " bytes, file has "
				.. tostring(#bytes)
				.. ")"
		)
	end

	local pos = 13 -- first chunk, right after the header
	local jsonText: string? = nil
	local binBytes: { number }? = nil

	while pos < totalLength do
		if pos + 8 > totalLength then
			error("gltf: .glb chunk header at offset " .. tostring(pos - 1) .. " runs past end of file")
		end
		local chunkLength = readUint32LE(bytes, pos)
		local t0, t1, t2, t3 = bytes[pos + 4], bytes[pos + 5], bytes[pos + 6], bytes[pos + 7]
		local chunkDataStart = pos + 8
		local chunkDataEnd = chunkDataStart + chunkLength - 1

		if t0 == 0x4A and t1 == 0x53 and t2 == 0x4F and t3 == 0x4E then -- "JSON"
			local chars: { string } = {}
			for i = chunkDataStart, chunkDataEnd do
				table.insert(chars, string.char(bytes[i]))
			end
			jsonText = table.concat(chars)
		elseif t0 == 0x42 and t1 == 0x49 and t2 == 0x4E and t3 == 0x00 then -- "BIN\0"
			-- slice so accessor offsets are relative to the buffer start
			local sliced: { number } = {}
			for i = chunkDataStart, chunkDataEnd do
				table.insert(sliced, bytes[i])
			end
			binBytes = sliced
		end
		-- unknown chunk types get skipped, per spec

		pos = chunkDataEnd + 1
	end

	if jsonText == nil then
		error("gltf: .glb has no JSON chunk")
	end

	local gltf = LuauJson.parse(jsonText)
	if gltf == nil then
		error("gltf: .glb JSON chunk is not valid JSON")
	end
	if type(gltf) ~= "table" then
		error("gltf: .glb JSON chunk is not an object")
	end

	local buffers = loadBuffers(gltf, binBytes, baseDir or "")
	return buildMesh(gltf, buffers, baseDir or "")
end

return Gltf
