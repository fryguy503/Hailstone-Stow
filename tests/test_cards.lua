local Cards = dofile("ui/modern/lib/stow_cards.lua")
local metrics = {pad = 4, gap = 5, tile = 31, tileGap = 3, header = 17}
local inputs = {
  {tiles = 8, columns = 7, captionWidth = 117},
  {tiles = 4, columns = 7, captionWidth = 90},
  {tiles = 5, columns = 7, captionWidth = 90},
  {tiles = 3, columns = 7, captionWidth = 70},
}

local packed = Cards.pack(inputs, 385, metrics)
local a, b, c, d = table.unpack(packed.boxes)
assert(a.x == 0 and a.y == 0 and a.columns == 7 and a.h == 86, "large card owns two snug tile rows")
assert(b.x == 0 and b.y == a.h + 5 and c.x == b.w + 5 and c.y == b.y, "medium cards share the next row")
assert(d.x == 0 and d.y == b.y + b.h + 5, "source order is stable and the last card wraps")
assert(packed.width == b.w + 5 + c.w and packed.width < 385, "width comes from the widest used row")

inputs[1].closed = true
local collapsed = Cards.pack(inputs, 385, metrics)
assert(collapsed.boxes[1].h == 17 and collapsed.boxes[1].w == 117, "folded card keeps only its caption")
assert(collapsed.height < packed.height, "folding large card reduces the body height")

local narrow = Cards.pack(inputs, 77, metrics)
assert(narrow.width <= 77 and narrow.boxes[2].columns == 2, "cards reflow their own slot grid on a narrow viewport")
for n, card in ipairs(narrow.boxes) do
  assert(card.w <= 77 and card.x == 0, "no side-by-side overflow")
  if n > 1 then assert(card.y > narrow.boxes[n - 1].y, "narrow order remains stable") end
end

local empty = Cards.pack({}, 385, metrics)
assert(empty.width == 0 and empty.height == 0 and #empty.boxes == 0, "no empty bounding panel")

local dock = Cards.anchor(800, 480, 300, 30, 1000, 600, "auto")
assert(dock.x == 700 and dock.y == 480 and dock.up and dock.room == 480, "lower-right dock may sit flush and grows up")
local small = Cards.bounds(dock, 300, 90, 5, 1000)
local large = Cards.bounds(dock, 440, 240, 5, 1000)
assert(small.y == 385 and large.y == 235 and small.y + small.height == large.y + large.height,
  "expansion changes the top edge while keeping the toolbar fixed")
assert(large.x == 560 and large.x + large.width == 1000, "a wider grid fits the screen without changing the dock anchor")
local high = Cards.anchor(-1, 0, 300, 30, 1000, 600, "auto")
assert(high.x == 0 and not high.up and high.room == 570, "upper-left dock may sit flush and grows down")
local down = Cards.anchor(800, 480, 300, 30, 1000, 600, "down")
assert(not down.up and down.room == 90, "manual down uses only the space below the dock")
local up = Cards.anchor(-1, 0, 300, 30, 1000, 600, "up")
assert(up.up and up.room == 0, "manual up at the top keeps the dock reachable without a body")
local x, y = Cards.migrate(820, 500, 300, 200, 30, 1000, 600, 8)
assert(x == 692 and y == 562, "migration preserves the old bottom-aligned dock position")
print("Stow card geometry tests passed")
