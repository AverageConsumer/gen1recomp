-- pokered/scripts/Route15Gate2F.asm: Route15Gate2FBinocularsText
-- text_asm just calls GateUpstairsScript_PrintIfFacingUp, which prints
-- the binoculars flavor text (no flags/branches involved).
return {
  ROUTE_15_GATE_2F = {
    talk = {
      -- Route15Gate2FBinocularsText -> .Text -> _Route15Gate2FBinocularsText
      TEXT_ROUTE15GATE2F_BINOCULARS = {
        { "show_text", "_Route15Gate2FBinocularsText" },
      },
    },
    -- engine/events/hidden_events/route_15_binoculars.asm:1-10
    onInteract = function(game, ow, fx, fy)
      if fx ~= 1 or fy ~= 2 or ow.player.facing ~= "up" then return false end
      local TextBox = require("src.render.TextBox")
      game.stack:push(TextBox.new(game,
        game.data.text._Route15UpstairsBinocularsText, function()
          require("src.core.Sound").playCry(game.data, "ARTICUNO")
          game.stack:push(require("src.ui.PicBox").new(game,
            "assets/generated/battle/front/articuno.png"))
        end))
      return true
    end,
  },
}
