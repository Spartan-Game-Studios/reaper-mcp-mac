-- reaper-mcp helper: load Surge XT .fxp patches into Surge XT VST3 instances by rewriting the FX state.
-- Jobs: /tmp/reaper_mcp_surge_jobs.txt, one per line: <track index>|<fx index>|<absolute .fxp path>
-- Log:  /tmp/reaper_mcp_surge_jobs.log, one line per job: <track>|<fx>|<ok>|<patch file>
--
-- Why: Surge XT doesn't expose its factory/3rd-party patches as REAPER presets (TrackFX_GetPresetIndex
-- reports 0), and the VST3 can't import .fxp. But Surge's VST3 state IS its patch data, so:
--   REAPER vst_chunk = int32 stateLen | int32 1 | [Surge patch data + JUCE trailer] | 8 zero bytes
--   Surge patch data = the .fxp file minus its 60-byte CcnK/FPCh header ("sub3" ... "</patch>")
--   JUCE trailer     = 16 zero bytes + "JUCEPrivateData"
-- Verified on Surge XT 1.3.x / REAPER 7.79: Surge re-serialises the loaded patch under its own name.
local function b64(data)
  local t = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local out = {}
  for i = 1, #data, 3 do
    local a, b, c = data:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = (n >> 18) & 63; local c2 = (n >> 12) & 63; local c3 = (n >> 6) & 63; local c4 = n & 63
    out[#out + 1] = t:sub(c1 + 1, c1 + 1) .. t:sub(c2 + 1, c2 + 1)
      .. (b and t:sub(c3 + 1, c3 + 1) or '=') .. (c and t:sub(c4 + 1, c4 + 1) or '=')
  end
  return table.concat(out)
end
local JUCE_TRAILER = string.rep('\0', 16) .. 'JUCEPrivateData'
local log = {}
local f = io.open('/tmp/reaper_mcp_surge_jobs.txt', 'r')
if f then
  for line in f:lines() do
    local ti, fi, path = line:match('^(%d+)|(%d+)|(.+)$')
    if ti then
      local pf = io.open(path, 'rb')
      if pf then
        local fxp = pf:read('a'); pf:close()
        local state = fxp:sub(61) .. JUCE_TRAILER
        local chunk = string.pack('<I4I4', #state, 1) .. state .. string.rep('\0', 8)
        local ok = reaper.TrackFX_SetNamedConfigParm(reaper.GetTrack(0, tonumber(ti)), tonumber(fi), 'vst_chunk', b64(chunk))
        log[#log + 1] = string.format('%s|%s|%s|%s', ti, fi, tostring(ok), path:match('[^/]+$'))
      else
        log[#log + 1] = ti .. '|' .. fi .. '|nofile|' .. path
      end
    end
  end
  f:close()
end
local o = io.open('/tmp/reaper_mcp_surge_jobs.log', 'w'); o:write(table.concat(log, '\n')); o:close()
