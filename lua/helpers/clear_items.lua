-- reaper-mcp helper: delete every media item on every track (keeps tracks, FX, patches, volumes).
for t = 0, reaper.CountTracks(0) - 1 do
  local tr = reaper.GetTrack(0, t)
  for i = reaper.CountTrackMediaItems(tr) - 1, 0, -1 do reaper.DeleteTrackMediaItem(tr, reaper.GetTrackMediaItem(tr, i)) end
end
reaper.UpdateArrange()
local o = io.open('/tmp/reaper_mcp_clear.log', 'w'); o:write('cleared ' .. os.date()); o:close()
