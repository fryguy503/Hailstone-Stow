local M = {}

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
