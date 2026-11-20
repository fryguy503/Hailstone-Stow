local M = {}

local function clamp(value, low, high)
  return math.max(low, math.min(value, high))
end

-- Convert the saved top-left of the old combined window to the position of its dock.
function M.migrate(x, y, width, height, dockHeight, viewportW, viewportH, margin)
  local oldX = clamp(x, margin, math.max(margin, viewportW - width - margin))
  local oldY = clamp(y, margin, math.max(margin, viewportH - height - margin))
  return oldX, oldY + math.max(0, height - dockHeight)
end

function M.anchor(x, y, width, height, viewportW, viewportH, growth)
  x = clamp(x, 0, math.max(0, viewportW - width))
  y = clamp(y, 0, math.max(0, viewportH - height))
  local below = math.max(0, viewportH - y - height)
  local up = growth == "up" or (growth ~= "down" and y >= below)
  return {x = x, y = y, width = width, height = height, up = up, room = up and y or below}
end

function M.bounds(dock, width, height, gap, viewportW)
  local x = clamp(dock.x, 0, math.max(0, viewportW - width))
  local y = dock.up and dock.y - gap - height or dock.y + dock.height + gap
  local left, top = math.min(x, dock.x), math.min(y, dock.y)
  local right = math.max(x + width, dock.x + dock.width)
  local bottom = math.max(y + height, dock.y + dock.height)
  return {x = left, y = top, width = right - left, height = bottom - top, contentX = x, contentY = y}
end

-- Stable, ordered wrapping. Each card keeps its own grid width and row count.
function M.pack(cards, limit, metrics)
  local pad, gap, step = metrics.pad, metrics.gap, metrics.tile + metrics.tileGap
  local availableCols = math.max(1, math.floor((limit - 2 * pad + metrics.tileGap) / step))
  local boxes, width = {}, 0
  local x, y, rowHeight = 0, 0, 0
  for n, card in ipairs(cards) do
    local columns = math.min(math.max(card.tiles, 1), card.columns, availableCols)
    local height = metrics.header
    local cardWidth = card.captionWidth or 0
    if not card.closed and card.tiles > 0 then
      local rows = math.ceil(card.tiles / columns)
      height = height + rows * step - metrics.tileGap + pad
      cardWidth = math.max(cardWidth, columns * step - metrics.tileGap + 2 * pad)
    end
    cardWidth = math.min(limit, cardWidth)
    if x > 0 and x + cardWidth > limit + 0.001 then
      x, y, rowHeight = 0, y + rowHeight + gap, 0
    end
    boxes[n] = {x = x, y = y, w = cardWidth, h = height, columns = columns}
    width = math.max(width, x + cardWidth)
    rowHeight = math.max(rowHeight, height)
    x = x + cardWidth + gap
  end
  return {boxes = boxes, width = width, height = y + rowHeight}
end

return M
