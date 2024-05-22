-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Decides the next action based on player proximity and energy.
-- Find weakest player in range and attack if energy advantage is significant.
function decideNextAction()
    local player = LatestGameState.Players[ao.id]
    local targetInRangeAndWeakest = nil
    local lowestEnergy = nil
  
    -- Iterate through all players to find the weakest player in range.
    for target, state in pairs(LatestGameState.Players) do
        if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 1) then
            if lowestEnergy == nil or state.energy < lowestEnergy then
                targetInRangeAndWeakest = target
                lowestEnergy = state.energy
            end
        end
    end
  
    -- If a target is found and player has sufficient energy, attack the weakest player.
    if targetInRangeAndWeakest and player.energy > 5 then
        local energyDifference = player.energy - lowestEnergy

        if energyDifference > 5 then
            print(colors.red .. "Weakest player in range and can be defeated. Attacking " .. targetInRangeAndWeakest .. "." .. colors.reset)
            ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(player.energy)})
        else
            -- If the energy difference is not significant, escape from the target.
            print(colors.blue .. "Weakest player in range but not a clear advantage. Escaping." .. colors.reset)
            escapeFrom(targetInRangeAndWeakest)
        end
    else
        -- If no player is in range, move randomly.
        print(colors.red .. "No player in range or insufficient energy. Moving randomly." .. colors.reset)
        moveRandomly()
    end
    InAction = false
  end

-- Moves the player to a random direction.
function moveRandomly()
    local directionMap = {"Up", "Down", "Left", "Right", "UpRight", "UpLeft", "DownRight", "DownLeft"}
    local randomIndex = math.random(#directionMap)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionMap[randomIndex]})
end

-- Escapes from a target player by moving in the opposite direction.
function escapeFrom(targetId)
    local player = LatestGameState.Players[ao.id]
    local target = LatestGameState.Players[targetId]

    -- Calculate the difference in x and y coordinates between the player and the target player.
    local dx = player.x - target.x
    local dy = player.y - target.y

    local escapeDirection = nil

    -- Invert the direction of the player to escape from the target player.
    if dx > 0 and dy > 0 then
        escapeDirection = "DownRight"
    elseif dx > 0 and dy < 0 then
        escapeDirection = "DownLeft"
    elseif dx < 0 and dy > 0 then
        escapeDirection = "UpRight"
    elseif dx < 0 and dy < 0 then
        escapeDirection = "UpLeft"
    elseif dx == 0 and dy > 0 then
        escapeDirection = "Down"
    elseif dx == 0 and dy < 0 then
        escapeDirection = "Up"
    elseif dx > 0 and dy == 0 then
        escapeDirection = "Right"
    elseif dx < 0 and dy == 0 then
        escapeDirection = "Left"
    end

    if escapeDirection then
        print(colors.blue .. "Escaping from " .. targetId .. " in direction " .. escapeDirection .. "." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = escapeDirection})
    else
        moveRandomly()
    end
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true -- InAction logic added
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then -- InAction logic added
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then
      InAction = false -- InAction logic added
      return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      local playerEnergy = LatestGameState.Players[ao.id].energy
      if playerEnergy == undefined then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        print(colors.red .. "Returning attack." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
      end
      InAction = false -- InAction logic added
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)