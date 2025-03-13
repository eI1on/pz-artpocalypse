require "ISUI/ISCollapsableWindow"

---@class PixelCanvas : ISCollapsableWindow
local PixelCanvas = ISCollapsableWindow:derive("PixelCanvas")
PixelCanvas.instance = nil

PixelCanvas.CANVAS_WIDTH = 400
PixelCanvas.CANVAS_HEIGHT = 400
PixelCanvas.PIXEL_SIZE = 3 -- fixed pixel size (canvas resolution)
PixelCanvas.BRUSH_SIZE = 1 -- initial brush size (in pixels)
PixelCanvas.MIN_BRUSH_SIZE = 1
PixelCanvas.MAX_BRUSH_SIZE = 10
PixelCanvas.DEFAULT_COLOR = { r = 0, g = 0, b = 0, a = 1 }
PixelCanvas.TOOLS = {
    PENCIL = "pencil",
    ERASER = "eraser",
    FILL = "fill",
    EYEDROPPER = "eyedropper",
    LINE = "line"
}
PixelCanvas.CHUNK_SIZE = 16   -- each chunk is 16x16 pixels

PixelCanvas.UI = {
    PADDING = 5,
    MARGIN = 10,
    BUTTON_HEIGHT = nil, -- will be set based on font height
    MIN_BUTTON_WIDTH = 60,
    COLOR_BUTTON_SIZE = 20,
    TOOLBAR_HEIGHT = 150 -- default value, will be calculated dynamically
}

PixelCanvas.COLOR_PRESETS = {
    { r = 0,   g = 0,   b = 0,   a = 1 }, -- Black
    { r = 1,   g = 1,   b = 1,   a = 1 }, -- White
    { r = 1,   g = 0,   b = 0,   a = 1 }, -- Red
    { r = 0,   g = 1,   b = 0,   a = 1 }, -- Green
    { r = 0,   g = 0,   b = 1,   a = 1 }, -- Blue
    { r = 1,   g = 1,   b = 0,   a = 1 }, -- Yellow
    { r = 1,   g = 0,   b = 1,   a = 1 }, -- Magenta
    { r = 0,   g = 1,   b = 1,   a = 1 }, -- Cyan
    { r = 0.5, g = 0,   b = 0,   a = 1 }, -- Brown
    { r = 1,   g = 0.5, b = 0,   a = 1 }, -- Orange
    { r = 0.5, g = 0.5, b = 0.5, a = 1 }, -- Gray
    { r = 0.7, g = 0.7, b = 1,   a = 1 }, -- Light blue
}

function PixelCanvas:initialise()
    ISCollapsableWindow.initialise(self)

    local fontHeight = getTextManager():getFontHeight(UIFont.Small)
    PixelCanvas.UI.BUTTON_HEIGHT = math.max(30, fontHeight + 10)

    self.pixelData = {}
    self.currentColor = PixelCanvas.DEFAULT_COLOR
    self.brushSize = PixelCanvas.BRUSH_SIZE
    self.currentTool = PixelCanvas.TOOLS.PENCIL
    self.isDrawing = false
    self.lastDrawX = -1
    self.lastDrawY = -1
    self.drawingHistory = {}
    self.historyIndex = 0
    self.maxHistorySize = 50
    self.undoStack = {}
    self.redoStack = {}

    self.pixelCache = {}
    self.cacheInvalid = true

    self.lineStartX = nil
    self.lineStartY = nil

    self.chunks = {}
    self.dirtyChunks = {}

    self.chunksX = math.ceil(PixelCanvas.CANVAS_WIDTH / (PixelCanvas.CHUNK_SIZE * PixelCanvas.PIXEL_SIZE))
    self.chunksY = math.ceil(PixelCanvas.CANVAS_HEIGHT / (PixelCanvas.CHUNK_SIZE * PixelCanvas.PIXEL_SIZE))

    self:clearCanvas()
end

function PixelCanvas:createChildren()
    self.canvasPanel = ISPanel:new(PixelCanvas.UI.MARGIN, 40, PixelCanvas.CANVAS_WIDTH, PixelCanvas.CANVAS_HEIGHT)
    self.canvasPanel:initialise()
    self.canvasPanel:instantiate()
    self.canvasPanel.backgroundColor = { r = 1, g = 1, b = 1, a = 1 }
    self.canvasPanel.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    self.canvasPanel.onMouseDown = self.onCanvasMouseDown
    self.canvasPanel.onMouseUp = self.onCanvasMouseUp
    self.canvasPanel.onMouseMove = self.onCanvasMouseMove
    self.canvasPanel.onMouseUpOutside = self.onCanvasMouseUp
    self.canvasPanel.parent = self
    self.canvasPanel.target = self
    self.canvasPanel.moveWithMouse = false
    self:addChild(self.canvasPanel)

    local toolbarY = self.canvasPanel:getY() + self.canvasPanel:getHeight() + PixelCanvas.UI.MARGIN
    self.toolbar = ISPanel:new(PixelCanvas.UI.MARGIN, toolbarY, PixelCanvas.CANVAS_WIDTH, PixelCanvas.UI.TOOLBAR_HEIGHT)
    self.toolbar:initialise()
    self.toolbar:instantiate()
    self.toolbar.backgroundColor = { r = 0.2, g = 0.2, b = 0.2, a = 0.8 }
    self.toolbar.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    self:addChild(self.toolbar)

    self:createToolButtons()

    self:createActionButtons()

    self:createColorPalette()

    self:createBrushControls()

    local maxY = 0
    for _, child in pairs(self.toolbar:getChildren()) do
        local childBottom = child:getY() + child:getHeight()
        if childBottom > maxY then
            maxY = childBottom
        end
    end

    local newToolbarHeight = maxY + PixelCanvas.UI.MARGIN
    PixelCanvas.UI.TOOLBAR_HEIGHT = newToolbarHeight
    self.toolbar:setHeight(newToolbarHeight)

    self:updateToolButtons()
end

function PixelCanvas:createToolButtons()
    local btnPadding = PixelCanvas.UI.PADDING
    local startX = PixelCanvas.UI.MARGIN
    local currentY = PixelCanvas.UI.MARGIN
    local btnHeight = PixelCanvas.UI.BUTTON_HEIGHT
    local currentX = startX

    local toolNames = {
        { internal = "pencil",     name = "Pencil" },
        { internal = "eraser",     name = "Eraser" },
        { internal = "fill",       name = "Fill" },
        { internal = "eyedropper", name = "Eyedropper" },
        { internal = "line",       name = "Line" }
    }

    self.toolButtons = {}

    for _, tool in ipairs(toolNames) do
        local button = ISButton:new(currentX, currentY, 30, btnHeight, tool.name, self, PixelCanvas.onToolButtonClick)
        button:initialise()
        button:instantiate()
        button:setFont(UIFont.Small)
        button:setWidthToTitle(PixelCanvas.UI.MIN_BUTTON_WIDTH)
        button.internal = tool.internal
        button.backgroundColor = { r = 0.5, g = 0.5, b = 0.5, a = 0.5 }
        button.backgroundColorMouseOver = { r = 0.7, g = 0.7, b = 0.7, a = 1 }
        self.toolbar:addChild(button)
        self.toolButtons[tool.internal] = button

        currentX = button:getRight() + btnPadding
    end

    self.nextRowY = btnHeight + PixelCanvas.UI.MARGIN + PixelCanvas.UI.PADDING
end

function PixelCanvas:createActionButtons()
    local btnPadding = PixelCanvas.UI.PADDING
    local startX = PixelCanvas.UI.MARGIN
    local currentY = self.nextRowY
    local btnHeight = PixelCanvas.UI.BUTTON_HEIGHT

    local actionButtons = {
        { internal = "clear", name = "Clear", color = { r = 0.5, g = 0.2, b = 0.2, a = 0.8 }, colorOver = { r = 0.7, g = 0.3, b = 0.3, a = 1 } },
        { internal = "undo",  name = "Undo",  color = { r = 0.3, g = 0.3, b = 0.5, a = 0.8 }, colorOver = { r = 0.4, g = 0.4, b = 0.7, a = 1 } },
        { internal = "redo",  name = "Redo",  color = { r = 0.3, g = 0.3, b = 0.5, a = 0.8 }, colorOver = { r = 0.4, g = 0.4, b = 0.7, a = 1 } },
        { internal = "save",  name = "Save",  color = { r = 0.2, g = 0.5, b = 0.2, a = 0.8 }, colorOver = { r = 0.3, g = 0.7, b = 0.3, a = 1 } },
        { internal = "load",  name = "Load",  color = { r = 0.2, g = 0.5, b = 0.2, a = 0.8 }, colorOver = { r = 0.3, g = 0.7, b = 0.3, a = 1 } }
    }

    local currentX = startX

    for _, action in ipairs(actionButtons) do
        local textWidth = getTextManager():MeasureStringX(UIFont.Small, action.name)
        local btnWidth = math.max(PixelCanvas.UI.MIN_BUTTON_WIDTH, textWidth + 20)

        local button = ISButton:new(currentX, currentY, btnWidth, btnHeight, action.name, self,
            PixelCanvas.onActionButtonClick)
        button:initialise()
        button:instantiate()
        button:setFont(UIFont.Small)
        button.internal = action.internal
        button.backgroundColor = action.color
        button.backgroundColorMouseOver = action.colorOver
        self.toolbar:addChild(button)

        if action.internal == "clear" then
            self.clearBtn = button
        elseif action.internal == "undo" then
            self.undoBtn = button
        elseif action.internal == "redo" then
            self.redoBtn = button
        elseif action.internal == "save" then
            self.saveBtn = button
        elseif action.internal == "load" then
            self.loadBtn = button
        end

        currentX = button:getRight() + btnPadding
    end

    self.nextRowY = currentY + btnHeight + PixelCanvas.UI.PADDING
end

function PixelCanvas:createColorPalette()
    local colorSize = PixelCanvas.UI.COLOR_BUTTON_SIZE
    local colorPadding = PixelCanvas.UI.PADDING
    local colorsPerRow = 6
    local colorX = PixelCanvas.UI.MARGIN
    local colorY = self.nextRowY

    local maxColorX = colorX
    local maxColorY = colorY

    for i = 1, #PixelCanvas.COLOR_PRESETS do
        local color = PixelCanvas.COLOR_PRESETS[i]
        local col = (i - 1) % colorsPerRow
        local row = math.floor((i - 1) / colorsPerRow)

        local x = colorX + col * (colorSize + colorPadding)
        local y = colorY + row * (colorSize + colorPadding)

        local colorBtn = ISButton:new(x, y, colorSize, colorSize, "", self, PixelCanvas.onColorButtonClick)
        colorBtn:initialise()
        colorBtn:instantiate()
        colorBtn.internal = i
        colorBtn.backgroundColor = color
        colorBtn.backgroundColorMouseOver = { r = color.r * 1.2, g = color.g * 1.2, b = color.b * 1.2, a = color.a }
        colorBtn.borderColor = { r = 1, g = 1, b = 1, a = 1 }
        self.toolbar:addChild(colorBtn)

        if x + colorSize > maxColorX then
            maxColorX = x + colorSize
        end

        if y + colorSize > maxColorY then
            maxColorY = y + colorSize
        end
    end

    local colorDisplayX = maxColorX + colorPadding * 2
    local colorDisplaySize = colorSize * 1.5

    self.currentColorDisplay = ISPanel:new(colorDisplayX, colorY, colorDisplaySize, colorDisplaySize)
    self.currentColorDisplay:initialise()
    self.currentColorDisplay:instantiate()
    self.currentColorDisplay.backgroundColor = self.currentColor
    self.currentColorDisplay.borderColor = { r = 1, g = 1, b = 1, a = 1 }
    self.toolbar:addChild(self.currentColorDisplay)

    self.brushControlX = self.currentColorDisplay:getRight() + PixelCanvas.UI.PADDING * 2
    self.brushControlY = colorY

    self.nextRowY = math.max(maxColorY, self.currentColorDisplay:getBottom()) + PixelCanvas.UI.PADDING

    self:createBrushControls()
end

function PixelCanvas:createBrushControls()
    local brushLabelText = "Brush Size: " .. self.brushSize
    local brushLabelHeight = getTextManager():getFontHeight(UIFont.Small)

    self.brushSizeLabel = ISLabel:new(
        self.brushControlX,
        self.brushControlY,
        brushLabelHeight,
        brushLabelText,
        1, 1, 1, 1,
        UIFont.Small,
        true
    )
    self.brushSizeLabel:initialise()
    self.brushSizeLabel:instantiate()
    self.toolbar:addChild(self.brushSizeLabel)

    local btnSize = brushLabelHeight + PixelCanvas.UI.PADDING

    local btnY = self.brushSizeLabel:getBottom() + PixelCanvas.UI.PADDING

    self.brushSizeDown = ISButton:new(
        self.brushControlX,
        btnY,
        btnSize,
        btnSize,
        "-",
        self,
        PixelCanvas.onBrushSizeButtonClick
    )
    self.brushSizeDown:initialise()
    self.brushSizeDown:instantiate()
    self.brushSizeDown.internal = "decrease"
    self.toolbar:addChild(self.brushSizeDown)

    self.brushSizeUp = ISButton:new(
        self.brushSizeDown:getRight() + PixelCanvas.UI.PADDING,
        btnY,
        btnSize,
        btnSize,
        "+",
        self,
        PixelCanvas.onBrushSizeButtonClick
    )
    self.brushSizeUp:initialise()
    self.brushSizeUp:instantiate()
    self.brushSizeUp.internal = "increase"
    self.toolbar:addChild(self.brushSizeUp)

    self.nextRowY = math.max(self.nextRowY,
        self.brushSizeUp:getBottom() + PixelCanvas.UI.PADDING)
end

function PixelCanvas:onToolButtonClick(button)
    if button.internal == "pencil" then
        self:setTool(PixelCanvas.TOOLS.PENCIL)
    elseif button.internal == "eraser" then
        self:setTool(PixelCanvas.TOOLS.ERASER)
    elseif button.internal == "fill" then
        self:setTool(PixelCanvas.TOOLS.FILL)
    elseif button.internal == "eyedropper" then
        self:setTool(PixelCanvas.TOOLS.EYEDROPPER)
    elseif button.internal == "line" then
        self:setTool(PixelCanvas.TOOLS.LINE)
    end
end

function PixelCanvas:onColorButtonClick(button)
    if button.internal and PixelCanvas.COLOR_PRESETS[button.internal] then
        self:setColor(PixelCanvas.COLOR_PRESETS[button.internal])
    end
end

function PixelCanvas:onBrushSizeButtonClick(button)
    if button.internal == "increase" then
        self:adjustBrushSize(1)
    elseif button.internal == "decrease" then
        self:adjustBrushSize(-1)
    end
end

function PixelCanvas:onActionButtonClick(button)
    if button.internal == "clear" then
        self:clearCanvas()
    elseif button.internal == "undo" then
        self:undo()
    elseif button.internal == "redo" then
        self:redo()
    elseif button.internal == "save" then
        self:saveCanvas()
    elseif button.internal == "load" then
        self:loadCanvasPrompt()
    end
end

function PixelCanvas:setTool(tool)
    self.currentTool = tool
    self:updateToolButtons()
    self.lineStartX = nil
    self.lineStartY = nil
end

function PixelCanvas:updateToolButtons()
    for toolName, button in pairs(self.toolButtons) do
        if self.currentTool == PixelCanvas.TOOLS[string.upper(toolName)] then
            button.backgroundColor = { r = 0.3, g = 0.7, b = 0.3, a = 1 }
        else
            button.backgroundColor = { r = 0.5, g = 0.5, b = 0.5, a = 0.5 }
        end
    end
end

function PixelCanvas:setColor(color)
    self.currentColor = { r = color.r, g = color.g, b = color.b, a = color.a }
    self.currentColorDisplay.backgroundColor = self.currentColor
end

function PixelCanvas:adjustBrushSize(delta)
    self.brushSize = (delta > 0) and
        math.min(PixelCanvas.MAX_BRUSH_SIZE, self.brushSize + delta) or
        math.max(PixelCanvas.MIN_BRUSH_SIZE, self.brushSize + delta)

    local brushSizeText = "Brush Size: " .. self.brushSize
    local textWidth = getTextManager():MeasureStringX(UIFont.Small, brushSizeText)

    self.brushSizeLabel:setName(brushSizeText)
    self.brushSizeLabel:setWidth(textWidth)
end

function PixelCanvas:clearCanvas()
    self.pixelData = {}
    self.chunks = {}
    self:markAllChunksDirty()
    self:saveToUndoStack()
end

function PixelCanvas:markChunkDirty(x, y)
    local chunkX = math.floor(x / (PixelCanvas.CHUNK_SIZE * PixelCanvas.PIXEL_SIZE))
    local chunkY = math.floor(y / (PixelCanvas.CHUNK_SIZE * PixelCanvas.PIXEL_SIZE))

    if chunkX >= 0 and chunkX < self.chunksX and
        chunkY >= 0 and chunkY < self.chunksY then
        local chunkKey = chunkX .. "," .. chunkY
        self.dirtyChunks[chunkKey] = true
    end
end

function PixelCanvas:markAreaDirty(x, y)
    local offset = math.floor(self.brushSize / 2)
    local pixelSize = PixelCanvas.PIXEL_SIZE

    local gridX = math.floor(x / pixelSize)
    local gridY = math.floor(y / pixelSize)

    self:markChunkDirty((gridX - offset) * pixelSize, (gridY - offset) * pixelSize)
    self:markChunkDirty((gridX + offset) * pixelSize, (gridY - offset) * pixelSize)
    self:markChunkDirty((gridX - offset) * pixelSize, (gridY + offset) * pixelSize)
    self:markChunkDirty((gridX + offset) * pixelSize, (gridY + offset) * pixelSize)
end

function PixelCanvas:markAllChunksDirty()
    for x = 0, self.chunksX - 1 do
        for y = 0, self.chunksY - 1 do
            local chunkKey = x .. "," .. y
            self.dirtyChunks[chunkKey] = true
        end
    end
end

function PixelCanvas:renderChunk(chunkX, chunkY)
    local chunkKey = chunkX .. "," .. chunkY

    if not self.chunks[chunkKey] then
        self.chunks[chunkKey] = {
            pixelData = {},     -- pixels in this chunk
            isEmpty = true,     -- is this chunk empty?
            needsRebuild = true -- does the chunk need rebuilding?
        }
    end

    local chunk = self.chunks[chunkKey]

    if not chunk.needsRebuild and chunk.isEmpty then
        self.dirtyChunks[chunkKey] = nil
        return
    end

    local startGridX = chunkX * PixelCanvas.CHUNK_SIZE
    local startGridY = chunkY * PixelCanvas.CHUNK_SIZE
    local endGridX = startGridX + PixelCanvas.CHUNK_SIZE - 1
    local endGridY = startGridY + PixelCanvas.CHUNK_SIZE - 1

    chunk.pixelData = {}
    chunk.isEmpty = true

    for gridX = startGridX, endGridX do
        for gridY = startGridY, endGridY do
            local key = gridX .. "," .. gridY
            local pixel = self.pixelData[key]

            if pixel then
                chunk.pixelData[key] = pixel
                chunk.isEmpty = false
            end
        end
    end

    chunk.needsRebuild = false
    self.dirtyChunks[chunkKey] = nil
end

function PixelCanvas:drawPixel(x, y, color)
    local gridX = math.floor(x / PixelCanvas.PIXEL_SIZE)
    local gridY = math.floor(y / PixelCanvas.PIXEL_SIZE)

    local offset = math.floor(self.brushSize / 2)
    local minGridX = gridX - offset
    local maxGridX = gridX + offset
    local minGridY = gridY - offset
    local maxGridY = gridY + offset

    local minChunkX = math.floor(minGridX / PixelCanvas.CHUNK_SIZE)
    local maxChunkX = math.floor(maxGridX / PixelCanvas.CHUNK_SIZE)
    local minChunkY = math.floor(minGridY / PixelCanvas.CHUNK_SIZE)
    local maxChunkY = math.floor(maxGridY / PixelCanvas.CHUNK_SIZE)

    for bx = -offset, offset do
        for by = -offset, offset do
            local finalX = gridX + bx
            local finalY = gridY + by

            if finalX >= 0 and finalX < (PixelCanvas.CANVAS_WIDTH / PixelCanvas.PIXEL_SIZE) and
                finalY >= 0 and finalY < (PixelCanvas.CANVAS_HEIGHT / PixelCanvas.PIXEL_SIZE) then
                local key = finalX .. "," .. finalY

                self.pixelData[key] = {
                    r = color.r,
                    g = color.g,
                    b = color.b,
                    a = color.a
                }
            end
        end
    end

    for chunkX = minChunkX, maxChunkX do
        for chunkY = minChunkY, maxChunkY do
            if chunkX >= 0 and chunkX < self.chunksX and
                chunkY >= 0 and chunkY < self.chunksY then
                local chunkKey = chunkX .. "," .. chunkY
                self.dirtyChunks[chunkKey] = true

                if self.chunks[chunkKey] then
                    self.chunks[chunkKey].needsRebuild = true
                end
            end
        end
    end
end

function PixelCanvas:erasePixel(x, y)
    local gridX = math.floor(x / PixelCanvas.PIXEL_SIZE)
    local gridY = math.floor(y / PixelCanvas.PIXEL_SIZE)

    local offset = math.floor(self.brushSize / 2)
    local minGridX = gridX - offset
    local maxGridX = gridX + offset
    local minGridY = gridY - offset
    local maxGridY = gridY + offset

    local minChunkX = math.floor(minGridX / PixelCanvas.CHUNK_SIZE)
    local maxChunkX = math.floor(maxGridX / PixelCanvas.CHUNK_SIZE)
    local minChunkY = math.floor(minGridY / PixelCanvas.CHUNK_SIZE)
    local maxChunkY = math.floor(maxGridY / PixelCanvas.CHUNK_SIZE)

    for bx = -offset, offset do
        for by = -offset, offset do
            local finalX = gridX + bx
            local finalY = gridY + by

            if finalX >= 0 and finalX < (PixelCanvas.CANVAS_WIDTH / PixelCanvas.PIXEL_SIZE) and
                finalY >= 0 and finalY < (PixelCanvas.CANVAS_HEIGHT / PixelCanvas.PIXEL_SIZE) then
                local key = finalX .. "," .. finalY
                self.pixelData[key] = nil
            end
        end
    end

    for chunkX = minChunkX, maxChunkX do
        for chunkY = minChunkY, maxChunkY do
            if chunkX >= 0 and chunkX < self.chunksX and
                chunkY >= 0 and chunkY < self.chunksY then
                local chunkKey = chunkX .. "," .. chunkY
                self.dirtyChunks[chunkKey] = true

                if self.chunks[chunkKey] then
                    self.chunks[chunkKey].needsRebuild = true
                end
            end
        end
    end
end

function PixelCanvas:getPixelColor(x, y)
    local gridX = math.floor(x / PixelCanvas.PIXEL_SIZE)
    local gridY = math.floor(y / PixelCanvas.PIXEL_SIZE)
    local key = gridX .. "," .. gridY

    return self.pixelData[key]
end

local directions = table.newarray(
    { dx = 1, dy = 0 },
    { dx = 0, dy = 1 },
    { dx = -1, dy = 0 },
    { dx = 0, dy = -1 }
)

function PixelCanvas:fillArea(startX, startY, targetColor)
    local startGridX = math.floor(startX / PixelCanvas.PIXEL_SIZE)
    local startGridY = math.floor(startY / PixelCanvas.PIXEL_SIZE)

    local maxX = math.floor(self.canvasPanel.width / PixelCanvas.PIXEL_SIZE) - 1
    local maxY = math.floor(self.canvasPanel.height / PixelCanvas.PIXEL_SIZE) - 1

    if startGridX < 0 or startGridX > maxX or startGridY < 0 or startGridY > maxY then
        return
    end

    local startKey = startGridX .. "," .. startGridY
    local replaceColor = self.pixelData[startKey]

    if replaceColor and self:colorsEqual(replaceColor, targetColor) then
        return
    end

    local modifiedChunks = {}

    local queue = table.newarray()
    local visited = {}
    local pixelsChanged = 0
    local MAX_PIXELS = 10000

    queue[1] = { x = startGridX, y = startGridY }
    visited[startKey] = true

    local pixelData = self.pixelData
    local chunksX = self.chunksX
    local chunksY = self.chunksY
    local chunkSize = PixelCanvas.CHUNK_SIZE

    while #queue > 0 and pixelsChanged < MAX_PIXELS do
---@diagnostic disable-next-line: param-type-mismatch
        local point = table.remove(queue, 1)
        local x, y = point.x, point.y
        local key = x .. "," .. y

        local currentColor = pixelData[key]
        local shouldFill = false

        if (replaceColor == nil and currentColor == nil) or
            (replaceColor ~= nil and currentColor ~= nil and self:colorsEqual(currentColor, replaceColor)) then
            shouldFill = true
        end

        if shouldFill then
            pixelData[key] = {
                r = targetColor.r,
                g = targetColor.g,
                b = targetColor.b,
                a = targetColor.a
            }
            pixelsChanged = pixelsChanged + 1

            local chunkX = math.floor(x / chunkSize)
            local chunkY = math.floor(y / chunkSize)
            local chunkKey = chunkX .. "," .. chunkY

            if chunkX >= 0 and chunkX < chunksX and
                chunkY >= 0 and chunkY < chunksY then
                modifiedChunks[chunkKey] = true
            end

            for i = 1, #directions do
                local dir = directions[i]
                local nx, ny = x + dir.dx, y + dir.dy

                if nx >= 0 and nx <= maxX and ny >= 0 and ny <= maxY then
                    local nkey = nx .. "," .. ny

                    if not visited[nkey] then
                        visited[nkey] = true
                        queue[#queue + 1] = { x = nx, y = ny }
                    end
                end
            end
        end
    end

    for chunkKey in pairs(modifiedChunks) do
        self.dirtyChunks[chunkKey] = true

        if self.chunks[chunkKey] then
            self.chunks[chunkKey].needsRebuild = true
        end
    end

    if pixelsChanged >= MAX_PIXELS then
        self:showMessage("Fill area too large - partially filled")
    end
end

function PixelCanvas:colorsEqual(color1, color2)
    if not color1 or not color2 then return false end
    return color1.r == color2.r and color1.g == color2.g and color1.b == color2.b and color1.a == color2.a
end

function PixelCanvas:drawLinePixels(x1, y1, x2, y2, color)
    local gridX1 = math.floor(x1 / PixelCanvas.PIXEL_SIZE)
    local gridY1 = math.floor(y1 / PixelCanvas.PIXEL_SIZE)
    local gridX2 = math.floor(x2 / PixelCanvas.PIXEL_SIZE)
    local gridY2 = math.floor(y2 / PixelCanvas.PIXEL_SIZE)

    --optimized Bresenham algorithm
    local steep = math.abs(gridY2 - gridY1) > math.abs(gridX2 - gridX1)

    if steep then
        gridX1, gridY1 = gridY1, gridX1
        gridX2, gridY2 = gridY2, gridX2
    end

    if gridX1 > gridX2 then
        gridX1, gridX2 = gridX2, gridX1
        gridY1, gridY2 = gridY2, gridY1
    end

    local dx = gridX2 - gridX1
    local dy = math.abs(gridY2 - gridY1)
    local err = dx / 2

    local ystep = (gridY1 < gridY2) and 1 or -1
    local y = gridY1

    local offset = math.floor(self.brushSize / 2)

    local modifiedChunks = {}

    for x = gridX1, gridX2 do
        if steep then
            for bx = -offset, offset do
                for by = -offset, offset do
                    local finalX = y + bx
                    local finalY = x + by

                    if finalX >= 0 and finalX < (PixelCanvas.CANVAS_WIDTH / PixelCanvas.PIXEL_SIZE) and
                        finalY >= 0 and finalY < (PixelCanvas.CANVAS_HEIGHT / PixelCanvas.PIXEL_SIZE) then
                        local key = finalX .. "," .. finalY
                        self.pixelData[key] = {
                            r = color.r,
                            g = color.g,
                            b = color.b,
                            a = color.a
                        }

                        local chunkX = math.floor(finalX / PixelCanvas.CHUNK_SIZE)
                        local chunkY = math.floor(finalY / PixelCanvas.CHUNK_SIZE)
                        local chunkKey = chunkX .. "," .. chunkY

                        if chunkX >= 0 and chunkX < self.chunksX and
                            chunkY >= 0 and chunkY < self.chunksY then
                            modifiedChunks[chunkKey] = true
                        end
                    end
                end
            end
        else
            for bx = -offset, offset do
                for by = -offset, offset do
                    local finalX = x + bx
                    local finalY = y + by

                    if finalX >= 0 and finalX < (PixelCanvas.CANVAS_WIDTH / PixelCanvas.PIXEL_SIZE) and
                        finalY >= 0 and finalY < (PixelCanvas.CANVAS_HEIGHT / PixelCanvas.PIXEL_SIZE) then
                        local key = finalX .. "," .. finalY
                        self.pixelData[key] = {
                            r = color.r,
                            g = color.g,
                            b = color.b,
                            a = color.a
                        }

                        local chunkX = math.floor(finalX / PixelCanvas.CHUNK_SIZE)
                        local chunkY = math.floor(finalY / PixelCanvas.CHUNK_SIZE)
                        local chunkKey = chunkX .. "," .. chunkY

                        if chunkX >= 0 and chunkX < self.chunksX and
                            chunkY >= 0 and chunkY < self.chunksY then
                            modifiedChunks[chunkKey] = true
                        end
                    end
                end
            end
        end

        err = err - dy
        if err < 0 then
            y = y + ystep
            err = err + dx
        end
    end

    for chunkKey in pairs(modifiedChunks) do
        self.dirtyChunks[chunkKey] = true

        if self.chunks[chunkKey] then
            self.chunks[chunkKey].needsRebuild = true
        end
    end
end

function PixelCanvas:saveToUndoStack()
    local currentState = {}
    for k, v in pairs(self.pixelData) do
        currentState[k] = { r = v.r, g = v.g, b = v.b, a = v.a }
    end

    self.redoStack = table.newarray()

    if not self.undoStack then
        self.undoStack = table.newarray()
    end
    self.undoStack[#self.undoStack + 1] = currentState

    if #self.undoStack > 50 then
        table.remove(self.undoStack, 1)
    end

    self.cacheInvalid = true
end

function PixelCanvas:undo()
    if not self.undoStack or #self.undoStack == 0 then return end

    local currentState = {}
    for k, v in pairs(self.pixelData) do
        currentState[k] = { r = v.r, g = v.g, b = v.b, a = v.a }
    end

    if not self.redoStack then
        self.redoStack = table.newarray()
    end
    self.redoStack[#self.redoStack + 1] = currentState

    local previousState = table.remove(self.undoStack)
    self.pixelData = previousState

    self:markAllChunksDirty()

    self.cacheInvalid = true
end

function PixelCanvas:redo()
    if not self.redoStack or #self.redoStack == 0 then return end

    local currentState = {}
    for k, v in pairs(self.pixelData) do
        currentState[k] = { r = v.r, g = v.g, b = v.b, a = v.a }
    end

    if not self.undoStack then
        self.undoStack = table.newarray()
    end
    self.undoStack[#self.undoStack + 1] = currentState

    local nextState = table.remove(self.redoStack)
    self.pixelData = nextState

    self:markAllChunksDirty()

    self.cacheInvalid = true
end

function PixelCanvas.onCanvasMouseDown(target, x, y)
    local self = target.parent or target.target
    if not self then return end

    local mouseX = target:getMouseX()
    local mouseY = target:getMouseY()

    self.isDrawing = true

    if self.currentTool == PixelCanvas.TOOLS.PENCIL then
        self:saveToUndoStack()
        self:drawPixel(mouseX, mouseY, self.currentColor)
        self.lastDrawX = mouseX
        self.lastDrawY = mouseY
    elseif self.currentTool == PixelCanvas.TOOLS.ERASER then
        self:saveToUndoStack()
        self:erasePixel(mouseX, mouseY)
        self.lastDrawX = mouseX
        self.lastDrawY = mouseY
    elseif self.currentTool == PixelCanvas.TOOLS.FILL then
        self:saveToUndoStack()
        self:fillArea(mouseX, mouseY, self.currentColor)
    elseif self.currentTool == PixelCanvas.TOOLS.EYEDROPPER then
        local color = self:getPixelColor(mouseX, mouseY)
        if color then
            self:setColor(color)
        end
    elseif self.currentTool == PixelCanvas.TOOLS.LINE then
        if not self.lineStartX then
            self.lineStartX = mouseX
            self.lineStartY = mouseY
        else
            self:saveToUndoStack()
            self:drawLinePixels(self.lineStartX, self.lineStartY, mouseX, mouseY, self.currentColor)
            self.lineStartX = nil
            self.lineStartY = nil
        end
    end

    return true
end

function PixelCanvas.onCanvasMouseMove(target, dx, dy)
    local self = target.parent or target.target
    if not self then return end

    if not self.isDrawing then return end

    local mouseX = target:getMouseX()
    local mouseY = target:getMouseY()

    if self.lastDrawX ~= -1 and self.lastDrawY ~= -1 then
        local deltaX = mouseX - self.lastDrawX
        local deltaY = mouseY - self.lastDrawY
        local distSquared = deltaX * deltaX + deltaY * deltaY

        local minMovementThreshold = 1.5
        if distSquared < minMovementThreshold * minMovementThreshold then
            return true
        end
    end

    if self.currentTool == PixelCanvas.TOOLS.PENCIL then
        if self.lastDrawX ~= -1 and self.lastDrawY ~= -1 then
            self:drawLinePixels(self.lastDrawX, self.lastDrawY, mouseX, mouseY, self.currentColor)
        else
            self:drawPixel(mouseX, mouseY, self.currentColor)
        end
        self.lastDrawX = mouseX
        self.lastDrawY = mouseY
    elseif self.currentTool == PixelCanvas.TOOLS.ERASER then
        self:optimizedErasePixel(mouseX, mouseY)
        self.lastDrawX = mouseX
        self.lastDrawY = mouseY
    end

    return true
end

function PixelCanvas.onCanvasMouseUp(target, x, y)
    local self = target.parent or target.target
    if not self then return end

    self.isDrawing = false
    self.lastDrawX = -1
    self.lastDrawY = -1

    return true
end

function PixelCanvas:prerender()
    ISCollapsableWindow.prerender(self)
end

function PixelCanvas:render()
    ISCollapsableWindow.render(self)
    self:renderCanvas()
end

function PixelCanvas:renderCanvas()
    if not self.canvasPanel then return end

    self.canvasPanel:drawRect(0, 0, self.canvasPanel.width, self.canvasPanel.height, 1, 1, 1, 1)

    local drawGrid = not self.isDrawing and PixelCanvas.PIXEL_SIZE > 1
    if drawGrid then
        local gridColor = { r = 0.9, g = 0.9, b = 0.9, a = 1 }
        for x = 0, self.canvasPanel.width, PixelCanvas.PIXEL_SIZE do
            self.canvasPanel:drawRect(x, 0, 1, self.canvasPanel.height, gridColor.a, gridColor.r, gridColor.g,
                gridColor.b)
        end
        for y = 0, self.canvasPanel.height, PixelCanvas.PIXEL_SIZE do
            self.canvasPanel:drawRect(0, y, self.canvasPanel.width, 1, gridColor.a, gridColor.r, gridColor.g, gridColor
                .b)
        end
    end

    for chunkKey in pairs(self.dirtyChunks) do
        local chunkX, chunkY = string.match(chunkKey, "(%d+),(%d+)")
        chunkX, chunkY = tonumber(chunkX), tonumber(chunkY)

        if chunkX and chunkY then
            self:renderChunk(chunkX, chunkY)
        end
    end

    for chunkX = 0, self.chunksX - 1 do
        for chunkY = 0, self.chunksY - 1 do
            local chunkKey = chunkX .. "," .. chunkY
            local chunk = self.chunks[chunkKey]

            if chunk and not chunk.isEmpty then
                for key, pixel in pairs(chunk.pixelData) do
                    local gridX, gridY = string.match(key, "(%d+),(%d+)")
                    gridX, gridY = tonumber(gridX), tonumber(gridY)

                    if gridX and gridY then
                        local screenX = gridX * PixelCanvas.PIXEL_SIZE
                        local screenY = gridY * PixelCanvas.PIXEL_SIZE

                        self.canvasPanel:drawRect(
                            screenX,
                            screenY,
                            PixelCanvas.PIXEL_SIZE,
                            PixelCanvas.PIXEL_SIZE,
                            pixel.a,
                            pixel.r,
                            pixel.g,
                            pixel.b
                        )
                    end
                end
            end
        end
    end

    if not self.isDrawing then
        if self.currentTool == PixelCanvas.TOOLS.LINE and self.lineStartX then
            self:renderLinePreview()
        end

        if self.currentTool ~= PixelCanvas.TOOLS.LINE and self.currentTool ~= PixelCanvas.TOOLS.FILL then
            self:renderBrushPreview()
        end
    end
end

function PixelCanvas:optimizedErasePixel(x, y)
    if self.brushSize <= 4 then
        return self:erasePixel(x, y)
    end

    local gridX = math.floor(x / PixelCanvas.PIXEL_SIZE)
    local gridY = math.floor(y / PixelCanvas.PIXEL_SIZE)

    local offset = math.floor(self.brushSize / 2)

    local minGridX = gridX - offset
    local maxGridX = gridX + offset
    local minGridY = gridY - offset
    local maxGridY = gridY + offset

    local minChunkX = math.floor(minGridX / PixelCanvas.CHUNK_SIZE)
    local maxChunkX = math.floor(maxGridX / PixelCanvas.CHUNK_SIZE)
    local minChunkY = math.floor(minGridY / PixelCanvas.CHUNK_SIZE)
    local maxChunkY = math.floor(maxGridY / PixelCanvas.CHUNK_SIZE)

    for chunkX = minChunkX, maxChunkX do
        for chunkY = minChunkY, maxChunkY do
            if chunkX >= 0 and chunkX < self.chunksX and
                chunkY >= 0 and chunkY < self.chunksY then
                local chunkKey = chunkX .. "," .. chunkY
                local chunkStartX = chunkX * PixelCanvas.CHUNK_SIZE
                local chunkStartY = chunkY * PixelCanvas.CHUNK_SIZE
                local chunkEndX = chunkStartX + PixelCanvas.CHUNK_SIZE - 1
                local chunkEndY = chunkStartY + PixelCanvas.CHUNK_SIZE - 1

                local overlapMinX = math.max(minGridX, chunkStartX)
                local overlapMaxX = math.min(maxGridX, chunkEndX)
                local overlapMinY = math.max(minGridY, chunkStartY)
                local overlapMaxY = math.min(maxGridY, chunkEndY)

                local hasOverlap = overlapMinX <= overlapMaxX and overlapMinY <= overlapMaxY

                if hasOverlap then
                    self.dirtyChunks[chunkKey] = true

                    for x = overlapMinX, overlapMaxX do
                        for y = overlapMinY, overlapMaxY do
                            local pixelKey = x .. "," .. y
                            local dx = x - gridX
                            local dy = y - gridY
                            local distSq = dx * dx + dy * dy
                            if distSq <= offset * offset then
                                self.pixelData[pixelKey] = nil
                            end
                        end
                    end

                    if self.chunks[chunkKey] then
                        self.chunks[chunkKey].needsRebuild = true
                    end
                end
            end
        end
    end
end

function PixelCanvas:buildOptimizedRenderRects()
    self.mergedRectangles = {}

    local pixelCount = 0
    for _ in pairs(self.pixelData) do
        pixelCount = pixelCount + 1
        if pixelCount > 100000 then break end
    end

    if pixelCount == 0 then
        self.cacheInvalid = false
        return
    end

    local grid = {}
    local maxGridX = math.floor(self.canvasPanel.width / PixelCanvas.PIXEL_SIZE) - 1
    local maxGridY = math.floor(self.canvasPanel.height / PixelCanvas.PIXEL_SIZE) - 1

    for key, color in pairs(self.pixelData) do
        local gridX, gridY = string.match(key, "(%d+),(%d+)")
        gridX, gridY = tonumber(gridX), tonumber(gridY)

        if gridX and gridY and gridX >= 0 and gridX <= maxGridX and gridY >= 0 and gridY <= maxGridY then
            grid[gridX] = grid[gridX] or {}
            grid[gridX][gridY] = color
        end
    end

    local scanLines = {}

    for y = 0, maxGridY do
        local linesForThisY = {}
        local startX = nil
        local currentColor = nil

        for x = 0, maxGridX + 1 do
            local pixelColor = nil
            if x <= maxGridX and grid[x] and grid[x][y] then
                pixelColor = grid[x][y]
            end

            if not startX and pixelColor then
                startX = x
                currentColor = pixelColor
                ---@diagnostic disable-next-line: need-check-nil, undefined-field
            elseif startX and (not pixelColor or pixelColor.r ~= currentColor.r or pixelColor.g ~= currentColor.g or pixelColor.b ~= currentColor.b or pixelColor.a ~= currentColor.a) then
                table.insert(linesForThisY, {
                    x = startX,
                    y = y,
                    width = x - startX,
                    color = currentColor
                })

                if pixelColor then
                    startX = x
                    currentColor = pixelColor
                else
                    startX = nil
                    currentColor = nil
                end
            end
        end

        if #linesForThisY > 0 then
            scanLines[y] = linesForThisY
        end
    end

    for y, lines in pairs(scanLines) do
        for _, line in ipairs(lines) do
            table.insert(self.mergedRectangles, {
                screenX = line.x * PixelCanvas.PIXEL_SIZE,
                screenY = line.y * PixelCanvas.PIXEL_SIZE,
                screenWidth = line.width * PixelCanvas.PIXEL_SIZE,
                screenHeight = PixelCanvas.PIXEL_SIZE,
                color = line.color
            })
        end
    end

    self.cacheInvalid = false
end

function PixelCanvas:renderLinePreview()
    local mouseX = self.canvasPanel:getMouseX()
    local mouseY = self.canvasPanel:getMouseY()

    local gridX1 = math.floor(self.lineStartX / PixelCanvas.PIXEL_SIZE)
    local gridY1 = math.floor(self.lineStartY / PixelCanvas.PIXEL_SIZE)
    local gridX2 = math.floor(mouseX / PixelCanvas.PIXEL_SIZE)
    local gridY2 = math.floor(mouseY / PixelCanvas.PIXEL_SIZE)

    local steep = math.abs(gridY2 - gridY1) > math.abs(gridX2 - gridX1)

    if steep then
        gridX1, gridY1 = gridY1, gridX1
        gridX2, gridY2 = gridY2, gridX2
    end

    if gridX1 > gridX2 then
        gridX1, gridX2 = gridX2, gridX1
        gridY1, gridY2 = gridY2, gridY1
    end

    local dx = gridX2 - gridX1
    local dy = math.abs(gridY2 - gridY1)
    local err = dx / 2

    local ystep = (gridY1 < gridY2) and 1 or -1
    local y = gridY1

    local offset = math.floor(self.brushSize / 2)

    local step = math.max(1, math.floor(dx / 100))

    for x = gridX1, gridX2, step do
        if steep then
            for bx = -offset, offset, 2 do
                for by = -offset, offset, 2 do
                    local previewX = (y + bx) * PixelCanvas.PIXEL_SIZE
                    local previewY = (x + by) * PixelCanvas.PIXEL_SIZE

                    if previewX >= 0 and previewX < self.canvasPanel.width and
                        previewY >= 0 and previewY < self.canvasPanel.height then
                        self.canvasPanel:drawRect(
                            previewX,
                            previewY,
                            PixelCanvas.PIXEL_SIZE,
                            PixelCanvas.PIXEL_SIZE,
                            0.3,
                            self.currentColor.r,
                            self.currentColor.g,
                            self.currentColor.b
                        )
                    end
                end
            end
        else
            for bx = -offset, offset, 2 do
                for by = -offset, offset, 2 do
                    local previewX = (x + bx) * PixelCanvas.PIXEL_SIZE
                    local previewY = (y + by) * PixelCanvas.PIXEL_SIZE

                    if previewX >= 0 and previewX < self.canvasPanel.width and
                        previewY >= 0 and previewY < self.canvasPanel.height then
                        self.canvasPanel:drawRect(
                            previewX,
                            previewY,
                            PixelCanvas.PIXEL_SIZE,
                            PixelCanvas.PIXEL_SIZE,
                            0.3,
                            self.currentColor.r,
                            self.currentColor.g,
                            self.currentColor.b
                        )
                    end
                end
            end
        end

        err = err - dy
        if err < 0 then
            y = y + ystep
            err = err + dx
        end
    end
end

function PixelCanvas:renderBrushPreview()
    local mouseX = self.canvasPanel:getMouseX()
    local mouseY = self.canvasPanel:getMouseY()

    if mouseX >= 0 and mouseX < self.canvasPanel.width and
        mouseY >= 0 and mouseY < self.canvasPanel.height then
        local gridX = math.floor(mouseX / PixelCanvas.PIXEL_SIZE)
        local gridY = math.floor(mouseY / PixelCanvas.PIXEL_SIZE)
        local offset = math.floor(self.brushSize / 2)

        for bx = -offset, offset do
            for by = -offset, offset do
                if bx == -offset or bx == offset or by == -offset or by == offset then
                    local previewX = (gridX + bx) * PixelCanvas.PIXEL_SIZE
                    local previewY = (gridY + by) * PixelCanvas.PIXEL_SIZE

                    if previewX >= 0 and previewX < self.canvasPanel.width and
                        previewY >= 0 and previewY < self.canvasPanel.height then
                        self.canvasPanel:drawRectBorder(
                            previewX,
                            previewY,
                            PixelCanvas.PIXEL_SIZE,
                            PixelCanvas.PIXEL_SIZE,
                            0.7,
                            self.currentColor.r,
                            self.currentColor.g,
                            self.currentColor.b
                        )
                    end
                end
            end
        end
    end
end

function PixelCanvas:saveCanvas()
    if self.saveDialog then
        self.saveDialog:close()
    end

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local dialogWidth = 300
    local dialogHeight = 120

    local x = (screenW - dialogWidth) / 2
    local y = (screenH - dialogHeight) / 2

    self.saveDialog = ISTextBox:new(
        x, y, dialogWidth, dialogHeight,
        "Enter name for your drawing:",
        "drawing1",
        self,
        PixelCanvas.onSaveDialogConfirm,
        self.player
    )
    self.saveDialog:initialise()
    self.saveDialog:addToUIManager()
    self.saveDialog:bringToTop()
end

function PixelCanvas:loadCanvasPrompt()
    local allDrawings = ModData.getOrCreate("PixelCanvasDrawings")
    local drawingNames = {}

    for name, _ in pairs(allDrawings) do
        table.insert(drawingNames, name)
    end

    if #drawingNames == 0 then
        self:showMessage("No saved drawings found.")
        return
    end

    if self.loadDialog then
        self.loadDialog:close()
    end

    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()
    local dialogWidth = 300
    local dialogHeight = 300

    local x = (screenW - dialogWidth) / 2
    local y = (screenH - dialogHeight) / 2

    self.loadDialog = ISModalDialog:new(
        x, y, dialogWidth, dialogHeight,
        "Select a drawing to load", true,
        self, PixelCanvas.onLoadDialogClose
    )
    self.loadDialog:initialise()

    local buttonHeight = getTextManager():getFontHeight(UIFont.Small) + 10
    local maxTextWidth = 0

    for _, name in ipairs(drawingNames) do
        local width = getTextManager():MeasureStringX(UIFont.Small, name)
        if width > maxTextWidth then
            maxTextWidth = width
        end
    end

    local buttonWidth = maxTextWidth + 20
    local buttonX = (dialogWidth - buttonWidth) / 2
    local startY = 50
    local buttonPadding = 5

    for i, name in ipairs(drawingNames) do
        local loadBtn = ISButton:new(buttonX, startY + (i - 1) * (buttonHeight + buttonPadding),
            buttonWidth, buttonHeight, name, self, PixelCanvas.loadCanvas)
        loadBtn:initialise()
        loadBtn:instantiate()
        loadBtn:setFont(UIFont.Small)
        loadBtn.internal = name
        self.loadDialog:addChild(loadBtn)
    end

    self.loadDialog:addToUIManager()
    self.loadDialog:bringToTop()
end

function PixelCanvas.onSaveDialogConfirm(target, button, filename)
    if button.internal == "OK" then
        if not filename or filename == "" then
            filename = "drawing1"
        end

        local serializedData = target:serializePixelData()

        local saveData = {
            name = filename,
            pixelSize = PixelCanvas.PIXEL_SIZE,
            brushSize = target.brushSize,
            serialized = serializedData,
        }

        local allDrawings = ModData.getOrCreate("PixelCanvasDrawings")
        allDrawings[filename] = saveData
        ModData.transmit("PixelCanvasDrawings")

        target:showMessage("Drawing saved as: " .. filename)
    end
end

function PixelCanvas:loadCanvas(button)
    local drawingName = button.internal
    local allDrawings = ModData.getOrCreate("PixelCanvasDrawings")
    local drawingData = allDrawings[drawingName]

    if drawingData then
        self.pixelData = {}

        if drawingData.brushSize then
            self.brushSize = drawingData.brushSize
        end

        local dataLoaded = false
        if drawingData.serialized then
            dataLoaded = self:deserializePixelData(drawingData.serialized)
        end

        if dataLoaded then
            self:saveToUndoStack()
            self:showMessage("Drawing loaded: " .. drawingName)

            local brushSizeText = "Brush Size: " .. self.brushSize
            local textWidth = getTextManager():MeasureStringX(UIFont.Small, brushSizeText)
            self.brushSizeLabel:setName(brushSizeText)
            self.brushSizeLabel:setWidth(textWidth)
        else
            self:showMessage("Error: Could not load drawing")
        end
    end

    if self.loadDialog then
        self.loadDialog:close()
        self.loadDialog = nil
    end
end

function PixelCanvas.onLoadDialogClose(target, button)
    if target.loadDialog then
        target.loadDialog:close()
        target.loadDialog = nil
    end
end

function PixelCanvas:serializePixelData()
    local width = PixelCanvas.CANVAS_WIDTH / PixelCanvas.PIXEL_SIZE
    local height = PixelCanvas.CANVAS_HEIGHT / PixelCanvas.PIXEL_SIZE

    -- building a palette of unique colors
    local palette = table.newarray()
    local colorToIndex = {}

    -- each unique color to the palette
    for _, color in pairs(self.pixelData) do
        local colorKey = string.format("%.3f,%.3f,%.3f,%.3f", color.r, color.g, color.b, color.a)
        if not colorToIndex[colorKey] then
            palette[#palette + 1] = { r = color.r, g = color.g, b = color.b, a = color.a }
            colorToIndex[colorKey] = #palette
        end
    end

    -- encode the pixel data using run-length encoding
    local rows = table.newarray()

    for y = 0, height - 1 do
        local runs = table.newarray()
        local x = 0

        while x < width do
            local key = x .. "," .. y
            local pixel = self.pixelData[key]
            local colorIndex = 0 -- 0 means transparent

            if pixel then
                local colorKey = string.format("%.3f,%.3f,%.3f,%.3f", pixel.r, pixel.g, pixel.b, pixel.a)
                colorIndex = colorToIndex[colorKey]
            end

            -- count how many consecutive pixels have this same color
            local runLength = 1
            while true do
                local nextX = x + runLength
                if nextX >= width then break end

                local nextKey = nextX .. "," .. y
                local nextPixel = self.pixelData[nextKey]
                local nextColorIndex = 0

                if nextPixel then
                    local nextColorKey = string.format("%.3f,%.3f,%.3f,%.3f", nextPixel.r, nextPixel.g, nextPixel.b,
                        nextPixel.a)
                    nextColorIndex = colorToIndex[nextColorKey]
                end

                if nextColorIndex ~= colorIndex then break end
                runLength = runLength + 1
            end

            runs[#runs + 1] = { colorIndex, x, runLength }
            x = x + runLength
        end

        rows[y + 1] = runs
    end

    return {
        width = width,
        height = height,
        palette = palette,
        rows = rows,
        format = "RLE",
        version = 1
    }
end

function PixelCanvas:deserializePixelData(data)
    if not data or data.format ~= "RLE" or not data.version then
        return false
    end

    self.pixelData = {}
    self.chunks = {}
    self.dirtyChunks = {}
    self.cacheInvalid = true

    local palette = data.palette

    for y = 0, data.height - 1 do
        local rowIndex = y + 1
        if rowIndex <= #data.rows then
            local runs = data.rows[rowIndex]

            for i = 1, #runs do
                local run = runs[i]
                local colorIndex = run[1]
                local startX = run[2]
                local runLength = run[3]

                if colorIndex > 0 and colorIndex <= #palette then
                    local color = palette[colorIndex]

                    for j = 0, runLength - 1 do
                        local x = startX + j
                        local key = x .. "," .. y

                        self.pixelData[key] = {
                            r = color.r,
                            g = color.g,
                            b = color.b,
                            a = color.a
                        }

                        local chunkX = math.floor(x / PixelCanvas.CHUNK_SIZE)
                        local chunkY = math.floor(y / PixelCanvas.CHUNK_SIZE)

                        if chunkX >= 0 and chunkX < self.chunksX and
                            chunkY >= 0 and chunkY < self.chunksY then
                            local chunkKey = chunkX .. "," .. chunkY
                            self.dirtyChunks[chunkKey] = true

                            if not self.chunks[chunkKey] then
                                self.chunks[chunkKey] = {
                                    pixelData = {},
                                    isEmpty = false,
                                    needsRebuild = true
                                }
                            else
                                self.chunks[chunkKey].needsRebuild = true
                                self.chunks[chunkKey].isEmpty = false
                            end
                        end
                    end
                end
            end
        end
    end
    self:markAllChunksDirty()
    return true
end

function PixelCanvas:showMessage(text)
    if self.messagePopup then
        self.messagePopup:close()
    end
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()

    local textWidth = getTextManager():MeasureStringX(UIFont.Medium, text)
    local textHeight = getTextManager():getFontHeight(UIFont.Medium)

    local dialogWidth = math.max(200, textWidth + 40)
    local dialogHeight = math.max(100, textHeight + 60)

    local x = (screenW - dialogWidth) / 2
    local y = (screenH - dialogHeight) / 2

    self.messagePopup = ISModalDialog:new(
        x, y, dialogWidth, dialogHeight,
        text, false, nil, nil
    )
    self.messagePopup:initialise()
    self.messagePopup:addToUIManager()
    self.messagePopup:bringToTop()

    self.messagePopupTicks = 0
    self.messagePopupTickFunction = function()
        self.messagePopupTicks = self.messagePopupTicks + 1
        if self.messagePopupTicks > 5000 then
            if self.messagePopup then
                self.messagePopup:close()
                self.messagePopup = nil
            end
            self.messagePopupTicks = 0
            Events.OnTick.Remove(self.messagePopupTickFunction)
        end
    end
    Events.OnTick.Add(self.messagePopupTickFunction)
end

function PixelCanvas:new(x, y, width, height)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.title = "Pixel Canvas"
    o.player = getPlayer():getPlayerNum()
    o:setResizable(false)
    return o
end

function PixelCanvas.openPanel()
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()

    if not PixelCanvas.UI.BUTTON_HEIGHT then
        local fontHeight = getTextManager():getFontHeight(UIFont.Small)
        PixelCanvas.UI.BUTTON_HEIGHT = math.max(30, fontHeight + 10)
    end

    local totalHeight = 40 + PixelCanvas.CANVAS_HEIGHT + PixelCanvas.UI.MARGIN + PixelCanvas.UI.TOOLBAR_HEIGHT

    local width = PixelCanvas.CANVAS_WIDTH + PixelCanvas.UI.MARGIN * 2
    local height = totalHeight + PixelCanvas.UI.MARGIN

    local x = (screenW - width) / 2
    local y = (screenH - height) / 2

    if not PixelCanvas.instance then
        local window = PixelCanvas:new(x, y, width, height)
        window:initialise()
        window:addToUIManager()
        PixelCanvas.instance = window

        if window.toolbar and window.toolbar:getHeight() ~= PixelCanvas.UI.TOOLBAR_HEIGHT then
            PixelCanvas.UI.TOOLBAR_HEIGHT = window.toolbar:getHeight()
            local newHeight = 40 + PixelCanvas.CANVAS_HEIGHT + PixelCanvas.UI.MARGIN + PixelCanvas.UI.TOOLBAR_HEIGHT +
                PixelCanvas.UI.MARGIN
            window:setHeight(newHeight)
        end
    else
        PixelCanvas.instance:close()
        PixelCanvas.instance = nil
    end
end

local function onFillWorldObjectContextMenu(playerNum, context, worldobjects, test)
    if not playerNum then return end

    context:addOption("Open Pixel Canvas", nil, function()
        PixelCanvas.openPanel()
    end)
end

Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)

Events.OnGameStart.Add(function()
    if not ModData.exists("PixelCanvasDrawings") then
        ModData.create("PixelCanvasDrawings")
    end
end)

return PixelCanvas
