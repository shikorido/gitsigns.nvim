local async = require('gitsigns.async')
local log = require('gitsigns.debug.log')
local util = require('gitsigns.util')

local asystem = async.wrap(3, require('gitsigns.system').system)

local PlenaryUtils = require("plenary.utils")

--- @class Gitsigns.Git.JobSpec : vim.SystemOpts
--- @field ignore_error? boolean

local function normalize_git_args(args)
  if util.win_git_flavor ~= 'msys2' then return args end

  local out = {}
  local i = 1

  while i <= #args do
    local arg = args[i]

    -- --git-dir=/path
    local k, v = arg:match('^(--git-dir)=(.+)$')
    if k then
      table.insert(out, k .. '=' .. PlenaryUtils.windows_to_posix(v))
      i = i + 1

    -- --work-tree=/path
    elseif arg:find('--work-tree=') then
      v = arg:match('^--work-tree=(.+)$')
      table.insert(out, '--work-tree=' .. PlenaryUtils.windows_to_posix(v))
      i = i + 1

    -- --git-dir /path
    -- --work-tree /path
    --elseif arg == '--git-dir' or arg == '--work-tree' then
    --  table.insert(out, arg)
    --  table.insert(out, cygpath(args[i + 1]))
    --  i = i + 2

    -- directory or file arguments
    elseif PlenaryUtils.is_windows_abs_path(arg) then
      table.insert(out, PlenaryUtils.windows_to_posix(arg))
      i = i + 1

    else
      table.insert(out, arg)
      i = i + 1
    end
  end

  return out
end

--- @async
--- @param args string[]
--- @param spec? Gitsigns.Git.JobSpec
--- @return string[] stdout, string? stderr, integer code
local function git_command(args, spec)
  spec = spec or {}
  if spec.cwd then
    -- cwd must be a windows path and not a unix path
    spec.cwd = util.cygpath(spec.cwd)
  end

  if PlenaryUtils.is_msys2 then
    args = normalize_git_args(args)
  end

  local cmd = {
    'git',
    '--no-pager',
    '--no-optional-locks',
    '--literal-pathspecs',
    '-c',
    'gc.auto=0', -- Disable auto-packing which emits messages to stderr
  }
  vim.list_extend(cmd, args)

  if spec.text == nil then
    spec.text = true
  end

  --- @type vim.SystemCompleted
  local obj = asystem(cmd, spec)
  async.schedule()

  if not spec.ignore_error and obj.code > 0 then
    log.eprintf(
      "Received exit code %d when running command\n'%s':\n%s",
      obj.code,
      table.concat(cmd, ' '),
      obj.stderr
    )
  end

  local stdout_lines = vim.split(obj.stdout or '', '\n')

  if spec.text then
    -- If stdout ends with a newline, then remove the final empty string after
    -- the split
    if stdout_lines[#stdout_lines] == '' then
      stdout_lines[#stdout_lines] = nil
    end
  end

  if PlenaryUtils.is_msys2 then
    for i, line in ipairs(stdout_lines) do
      if PlenaryUtils.is_posix_abs_path(line) then
        stdout_lines[i] = PlenaryUtils.posix_to_windows(line, "/")
      end
    end
  end

  if log.verbose then
    log.vprintf('%d lines:', #stdout_lines)
    for i = 1, math.min(10, #stdout_lines) do
      log.vprintf('\t%s', stdout_lines[i])
    end
  end

  if obj.stderr == '' then
    obj.stderr = nil
  end

  return stdout_lines, obj.stderr, obj.code
end

return git_command
