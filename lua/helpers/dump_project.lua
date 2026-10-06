-- reaper-mcp helper: dump master + every track (name, volume, mute, items, every note, CC count) to
-- /tmp/reaper_mcp_dump.txt. Use it to sync an arrangement script after the user edits by hand.
local out = {}
out[#out + 1] = string.format('MASTER vol=%.4f', reaper.GetMediaTrackInfo_Value(reaper.GetMasterTrack(0), 'D_VOL'))
for t = 0, reaper.CountTracks(0) - 1 do
  local tr = reaper.GetTrack(0, t)
  local _, name = reaper.GetTrackName(tr)
  out[#out + 1] = string.format('TRACK %d %s vol=%.4f mute=%d', t, name, reaper.GetMediaTrackInfo_Value(tr, 'D_VOL'), reaper.GetMediaTrackInfo_Value(tr, 'B_MUTE'))
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local tk = reaper.GetActiveTake(reaper.GetTrackMediaItem(tr, i))
    if tk and reaper.TakeIsMIDI(tk) then
      local _, nn, nc = reaper.MIDI_CountEvts(tk)
      out[#out + 1] = string.format('  item %d notes=%d ccs=%d', i, nn, nc)
      for k = 0, nn - 1 do
        local _, _, mu, s, e, _, p, v = reaper.MIDI_GetNote(tk, k)
        local qs = reaper.MIDI_GetProjQNFromPPQPos(tk, s)
        out[#out + 1] = string.format('  N %.3f %.3f %d %d%s', qs, reaper.MIDI_GetProjQNFromPPQPos(tk, e) - qs, p, v, mu and ' muted' or '')
      end
    end
  end
end
local o = io.open('/tmp/reaper_mcp_dump.txt', 'w'); o:write(table.concat(out, '\n')); o:close()
