-- reaper-mcp helper: write a whole arrangement from /tmp/reaper_mcp_midi.txt into the current project.
-- Lines:
--   <track>|<start_qn>|<len_qn>|<pitch>|<velocity>     a note (channel 1)
--   P|<track>|<qn>|<value>                            channel pressure / aftertouch (e.g. MPE "breath")
--   C|<track>|<qn>|<cc number>|<value>                a CC
--   LEN|<qn>                                          item length (default: the last note's end)
-- Creates ONE MIDI item per track from 0 (doesn't clear first: run clear_items.lua before a rewrite).
-- Log: /tmp/reaper_mcp_midi.log ("notes N ccs M").
local lines, last = {}, 0
for line in io.lines('/tmp/reaper_mcp_midi.txt') do
  lines[#lines + 1] = line
  local s, l = line:match('^%d+|([%d%.]+)|([%d%.]+)|')
  if s then last = math.max(last, tonumber(s) + tonumber(l)) end
  local fixed = line:match('^LEN|([%d%.]+)$'); if fixed then last = tonumber(fixed) end
end
local items = {}
local function take_for(t)
  if items[t] then return items[t] end
  local it = reaper.CreateNewMIDIItemInProj(reaper.GetTrack(0, t), 0, reaper.TimeMap_QNToTime(last), false)
  items[t] = reaper.GetActiveTake(it)
  return items[t]
end
local n, c = 0, 0
for _, line in ipairs(lines) do
  local pt, ps, pv = line:match('^P|(%d+)|([%d%.]+)|(%d+)$')
  if pt then
    local tk = take_for(tonumber(pt))
    reaper.MIDI_InsertCC(tk, false, false, reaper.MIDI_GetPPQPosFromProjQN(tk, tonumber(ps)), 0xD0, 0, tonumber(pv), 0)
    c = c + 1
  end
  local ct, cs, cn, cv = line:match('^C|(%d+)|([%d%.]+)|(%d+)|(%d+)$')
  if ct then
    local tk = take_for(tonumber(ct))
    reaper.MIDI_InsertCC(tk, false, false, reaper.MIDI_GetPPQPosFromProjQN(tk, tonumber(cs)), 0xB0, 0, tonumber(cn), tonumber(cv))
    c = c + 1
  end
  local t, s, l, p, v = line:match('^(%d+)|([%d%.]+)|([%d%.]+)|(%d+)|(%d+)$')
  if t then
    local tk = take_for(tonumber(t))
    reaper.MIDI_InsertNote(tk, false, false, reaper.MIDI_GetPPQPosFromProjQN(tk, tonumber(s)),
      reaper.MIDI_GetPPQPosFromProjQN(tk, tonumber(s) + tonumber(l)), 0, tonumber(p), tonumber(v), true)
    n = n + 1
  end
end
for _, tk in pairs(items) do reaper.MIDI_Sort(tk) end
reaper.UpdateArrange()
local o = io.open('/tmp/reaper_mcp_midi.log', 'w'); o:write('notes ' .. n .. ' ccs ' .. c); o:close()
