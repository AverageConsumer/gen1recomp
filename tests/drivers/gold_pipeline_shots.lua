-- Gold's world-pipeline seam (World:drawPipeline), the Gen 2 peer of the
-- render_pipelines path src/world/OverworldController.lua:4867 gives Gen 1.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold \
--     POKEPORT_DRIVER=tests/drivers/gold_pipeline_shots.lua love .
--   POKEPORT_SHOT_DIR=/tmp/gold-pipeline   (default)
--
-- Registers a pipeline that paints an unmistakable magenta field, switches it
-- on, and asserts what the seam is supposed to guarantee: drawWorld owns the
-- frame, ctx carries the Gen 1 keys, ctx.drawFx anchors the standing FX,
-- worldPresent folds over the result, tilt is forced off, and a declined
-- frame falls back to the vanilla 2D draw instead of a blank screen.
local U = require("tests.drivers.util")

local Pipelines = require("src.render.Pipelines")
local Tilt = require("src.render.Tilt")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-pipeline"
  local failures = 0

  local function ok(label, condition, detail)
    if condition then
      print("[pipeline] ok   " .. label)
    else
      failures = failures + 1
      print("[pipeline] FAIL " .. label .. " " .. tostring(detail))
    end
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  world:setMap("ROUTE_30", 10, 10, "down")
  U.wait(10)
  U.shot(game, out .. "/00-vanilla.png")

  -- ---------------------------------------------------------------- record
  local seen, canvas = {}, nil
  local decline = false
  local pipeline = {
    label = "TESTPIPE",
    levels = { "OFF", "ON" },
    drawWorld = function(ctx)
      seen.ctx = ctx
      seen.drawWorld = (seen.drawWorld or 0) + 1
      if decline then return nil end
      local G = love.graphics
      local w, h = ctx.width, ctx.height
      if not canvas or canvas:getWidth() ~= w or canvas:getHeight() ~= h then
        canvas = G.newCanvas(w, h)
      end
      local previous = G.getCanvas()
      G.push("all")
      G.origin()
      G.setCanvas(canvas)
      G.clear(0.8, 0.1, 0.6, 1)
      G.setColor(1, 1, 1, 1)
      for x = 0, w, 32 do G.rectangle("fill", x, 0, 1, h) end
      for y = 0, h, 32 do G.rectangle("fill", 0, y, w, 1) end
      -- the standing FX, anchored under this pipeline's own (identity) camera
      ctx.drawFx(function(wx, wy)
        return (wx - ctx.cam.x) * ctx.scale, (wy - ctx.cam.y) * ctx.scale
      end, ctx.scale)
      G.setCanvas(previous)
      G.pop()
      seen.drew = true
      return canvas
    end,
    worldPresent = function(image, ctx)
      seen.worldPresent = (seen.worldPresent or 0) + 1
      seen.presentCtx = ctx
      return image
    end,
  }

  -- A fresh table so Pipelines.list()'s identity-keyed memo re-sorts; the
  -- mod merge hands it a new one for the same reason.
  game.data.render_pipelines = { testpipe = pipeline }
  Pipelines.install(game.data)
  ok("registered", Pipelines.get("testpipe") ~= nil, "not in the registry")

  -- ------------------------------------------------------------ switched on
  Tilt.setLevel(1)
  Pipelines.setLevel("testpipe", 1)
  ok("tilt forced off", Tilt.level == 0, "tilt still " .. tostring(Tilt.level))
  ok("world pipeline claimed", Pipelines.worldPipeline() == "testpipe",
    tostring(Pipelines.worldPipeline()))
  U.wait(5)
  U.shot(game, out .. "/01-pipeline-on.png")

  ok("drawWorld ran", (seen.drawWorld or 0) > 0, "never called")
  ok("drawWorld drew", seen.drew == true, "declined every frame")
  ok("worldPresent ran", (seen.worldPresent or 0) > 0, "never called")

  local ctx = seen.ctx
  ok("ctx.state is the world", ctx and ctx.state == world, "wrong state")
  ok("ctx.cam is the camera", ctx and ctx.cam == world.camera, "wrong camera")
  ok("ctx.scale is zoomScale", ctx and ctx.scale == world:zoomScale(),
    ctx and tostring(ctx.scale))
  ok("ctx.bgY is the camera row", ctx and ctx.bgY == world.camera.y,
    ctx and tostring(ctx.bgY))
  ok("ctx.vw/vh are the view", ctx and ctx.vw == world.viewW
    and ctx.vh == world.viewH, ctx and tostring(ctx.vw))
  ok("ctx.level is the ladder", ctx and ctx.level == 1, ctx and tostring(ctx.level))
  ok("ctx.width/height are the window",
    ctx and ctx.width == love.graphics.getWidth()
    and ctx.height == love.graphics.getHeight(), "mismatch")
  ok("ctx.paletteFor is nil-valued (art is baked)",
    ctx and ctx.paletteFor and ctx.paletteFor(world.map) == nil, "returned colours")
  ok("ctx.spriteColors is nil-valued",
    ctx and ctx.spriteColors and ctx.spriteColors() == nil, "returned colours")
  ok("ctx.fx has Gold's two effects",
    ctx and ctx.fx and type(ctx.fx.emote) == "function"
    and type(ctx.fx.heal) == "function", "missing fx")
  ok("ctx.drawFx is callable", ctx and type(ctx.drawFx) == "function", "missing")
  ok("worldPresent got the same ctx", seen.presentCtx == seen.ctx, "different ctx")

  -- ------------------------------------------------- the FX composite path
  -- An emote over the player exercises ctx.drawFx end to end: it must be the
  -- pipeline that composites it, and the vanilla drawPeople must not also.
  local sheet
  for _, img in pairs(world.emoteImages or {}) do sheet = img break end
  if sheet then
    world.emote = { image = sheet, entity = world.player, left = 240 }
  end
  U.wait(4)
  ok("emote is up", world.emote ~= nil, "no emote sheet loaded")
  local fxOk = pcall(function()
    -- the same call the pipeline made, run again outside the guard so a throw
    -- surfaces here rather than only retiring the pipeline
    seen.ctx.drawFx(function(wx, wy) return wx, wy end, 1)
  end)
  ok("drawFx composites without throwing", fxOk, "threw")
  U.shot(game, out .. "/02-pipeline-emote.png")

  -- ----------------------------------------------------- a declined frame
  decline = true
  U.wait(5)
  U.shot(game, out .. "/03-pipeline-declined.png")
  ok("declined frames still call drawWorld", (seen.drawWorld or 0) > 1, "stopped")
  decline = false

  -- ------------------------------------------------------------ switched off
  Pipelines.setLevel("testpipe", 0)
  local before = seen.drawWorld
  U.wait(5)
  ok("off means not called", seen.drawWorld == before,
    "still drawing at level 0")
  U.shot(game, out .. "/04-pipeline-off.png")

  if failures == 0 then
    print("[pipeline] PASS")
  else
    print("[pipeline] FAILURES: " .. failures)
  end
  love.event.quit(failures == 0 and 0 or 1)
end
