-- reaper-mcp helper: render every track soloed (whole project) to /tmp/reaper_mcp_stems/<index>.wav, then
-- restore solos and render settings. Writes /tmp/reaper_mcp_stems/done.txt when finished.
-- Takes longer than the bridge's 15 s timeout: the call times out but REAPER keeps going; poll done.txt.
-- Delete the folder first: REAPER never overwrites a render (it writes <name>-001.wav instead).
local n = reaper.CountTracks(0)
os.execute('mkdir -p /tmp/reaper_mcp_stems')
local _, oldfile = reaper.GetSetProjectInfo_String(0, 'RENDER_FILE', '', false)
local _, oldpat = reaper.GetSetProjectInfo_String(0, 'RENDER_PATTERN', '', false)
local oldbounds = reaper.GetSetProjectInfo(0, 'RENDER_BOUNDSFLAG', 0, false)
local oldsolo = {}
for j = 0, n - 1 do oldsolo[j] = reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, j), 'I_SOLO') end
for i = 0, n - 1 do
  for j = 0, n - 1 do reaper.SetMediaTrackInfo_Value(reaper.GetTrack(0, j), 'I_SOLO', j == i and 2 or 0) end
  reaper.GetSetProjectInfo_String(0, 'RENDER_FILE', '/tmp/reaper_mcp_stems', true)
  reaper.GetSetProjectInfo_String(0, 'RENDER_PATTERN', tostring(i), true)
  reaper.GetSetProjectInfo(0, 'RENDER_BOUNDSFLAG', 1, true)
  reaper.Main_OnCommand(42230, 0) -- File: Render project, using the most recent render settings, auto-close
end
for j = 0, n - 1 do reaper.SetMediaTrackInfo_Value(reaper.GetTrack(0, j), 'I_SOLO', oldsolo[j]) end
reaper.GetSetProjectInfo_String(0, 'RENDER_FILE', oldfile, true)
reaper.GetSetProjectInfo_String(0, 'RENDER_PATTERN', oldpat, true)
reaper.GetSetProjectInfo(0, 'RENDER_BOUNDSFLAG', oldbounds, true)
local o = io.open('/tmp/reaper_mcp_stems/done.txt', 'w'); o:write('ok'); o:close()
