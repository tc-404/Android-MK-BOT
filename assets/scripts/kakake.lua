-- kakake.lua · 咔咔珂框架 (Ubuntu 容器内安装 / Node / 启停 / 连接配置)
-- 功能对齐 mk 脚本 menu_kakake 全套, 适配 Android DIY Sandbox

local M = {}

M.SPAWN_KEY = "kakake"
M.INSTALL_KEY = "kakake_install"
M.NODE_INSTALL_KEY = "kakake_node_install"
M.ADMIN_PORT = 8787
M.DEFAULT_REV_PORT = 6700
M.DEFAULT_FWD_PORT = 3001
M.KAKAKE_HOME = "/root/kakake"
M.NODE_DIR = "/root/.diy-sandbox/nodejs"
M.NODE_BIN = M.NODE_DIR .. "/bin/node"
M.INSTALL_STEPS = 5
M.NODE_INSTALL_STEPS = 4

local _installed_cache = nil
local _node_cache = nil
local _poll_id = nil

-- ============================================================
-- 路径
-- ============================================================

local function ub(path)
  if not path or path == "" then return host.ubuntu_path() end
  if path:sub(1, 1) == "/" then return host.ubuntu_path() .. path end
  return host.ubuntu_path() .. "/" .. path
end

function M.home_path() return ub(M.KAKAKE_HOME) end
function M.conn_file() return ub(M.KAKAKE_HOME .. "/data/connections.json") end
function M.pkg_file() return ub(M.KAKAKE_HOME .. "/package.json") end
function M.bootstrap_file() return ub(M.KAKAKE_HOME .. "/scripts/bootstrap.mjs") end
function M.runtime_log() return host.tmp_path() .. "/kakake-runtime.log" end
function M.pid_file() return host.tmp_path() .. "/kakake.pid" end

function M.admin_url()
  local p = tonumber(host.get("kakake_admin_port"))
  return "http://127.0.0.1:" .. (p or M.ADMIN_PORT)
end

function M.admin_port()
  return tonumber(host.get("kakake_admin_port")) or M.ADMIN_PORT
end

-- ============================================================
-- 下载源 / Node 镜像
-- ============================================================

M.DOWNLOAD_URLS = {
  "https://xn--mk-ub3cl61ae1v.xn--c5w857b.xn--fiqs8s/mkbot/kakake.zip",
  "https://ghfast.top/https://xn--mk-ub3cl61ae1v.xn--c5w857b.xn--fiqs8s/mkbot/kakake.zip",
  "https://gh-proxy.com/https://xn--mk-ub3cl61ae1v.xn--c5w857b.xn--fiqs8s/mkbot/kakake.zip",
}

M.NODE_VERSIONS = {
  { label = "22.23.0 (22.x LTS, 推荐)", value = "22.23.0" },
  { label = "20.19.2 (20.x LTS)",       value = "20.19.2" },
}

M.NODE_MIRRORS = {
  { label = "npmmirror (淘宝源, 推荐)", value = "https://npmmirror.com/mirrors/node" },
  { label = "官方 nodejs.org",          value = "https://nodejs.org/dist" },
  { label = "腾讯云镜像",               value = "https://mirrors.cloud.tencent.com/nodejs-release" },
  { label = "华为云镜像",               value = "https://repo.huaweicloud.com/nodejs" },
  { label = "清华大学镜像",             value = "https://mirrors.tuna.tsinghua.edu.cn/nodejs-release" },
}

function M.node_version()
  return host.get("kakake_node_version") or "22.23.0"
end

function M.node_mirror()
  return host.get("kakake_node_mirror") or "https://npmmirror.com/mirrors/node"
end

function M.node_mirror_label()
  local v = M.node_mirror()
  for _, m in ipairs(M.NODE_MIRRORS) do
    if m.value == v then return m.label end
  end
  return v
end

-- ============================================================
-- 状态检测
-- ============================================================

function M.invalidate_cache()
  _installed_cache = nil
  _node_cache = nil
end

function M.installed(force)
  if not force and _installed_cache ~= nil then return _installed_cache end
  local ok = host.exists(M.pkg_file()) and host.exists(M.bootstrap_file())
  _installed_cache = ok
  return ok
end

function M.node_installed(force)
  if not force and _node_cache ~= nil then return _node_cache end
  local ok = host.exists(ub(M.NODE_BIN))
  _node_cache = ok
  return ok
end

function M.is_running(ctx)
  if ctx and ctx.running and ctx.running[M.SPAWN_KEY] == true then return true end
  return host.spawn_running(M.SPAWN_KEY) == true
end

function M.node_version_text()
  if not M.node_installed(true) then return "未安装" end
  -- 版本记录在设置中
  local v = host.get("kakake_node_installed_ver")
  return v and ("v" .. v) or "已安装"
end

-- ============================================================
-- 连接配置 (纯 Lua + json, 对齐 mk kakake_cfg_tool)
-- ============================================================

function M.default_connections()
  return {
    connections = {
      {
        id = "default",
        name = "NapCat 默认接入",
        type = "onebot",
        mode = "reverse",
        host = "127.0.0.1",
        port = M.DEFAULT_REV_PORT,
        accessToken = "",
        enable = false,
      },
    },
  }
end

function M.cfg_load()
  local raw = host.read_file(M.conn_file())
  if not raw or raw == "" then return M.default_connections() end
  local ok, data = pcall(json.decode, raw)
  if ok and data and type(data.connections) == "table" then return data end
  return M.default_connections()
end

function M.cfg_save(data)
  host.write_file(M.conn_file(), json.encode(data))
end

function M.cfg_list()
  local data = M.cfg_load()
  local rows = {}
  for i, c in ipairs(data.connections or {}) do
    local cat = c.type or "onebot"
    if cat == "onebot" then cat = "onebot:" .. (c.mode or "reverse") end
    local addr = ""
    if cat == "qq_official" then
      addr = "AppID " .. (c.appId or "")
    elseif (c.mode or "reverse") == "forward" then
      addr = "ws://" .. (c.host or "127.0.0.1") .. ":" .. (c.port or M.DEFAULT_FWD_PORT)
    else
      addr = (c.host or "0.0.0.0") .. ":" .. (c.port or M.DEFAULT_REV_PORT)
    end
    rows[#rows + 1] = {
      idx = i - 1,
      name = c.name or ("连接" .. i),
      category = cat,
      addr = addr,
      enable = c.enable == true,
      raw = c,
    }
  end
  return rows
end

function M.cfg_add_onebot_reverse(name, host_addr, port, token, enable)
  local data = M.cfg_load()
  data.connections = data.connections or {}
  data.connections[#data.connections + 1] = {
    id = host.uuid():gsub("-", ""):sub(1, 12),
    name = name,
    type = "onebot",
    mode = "reverse",
    host = host_addr or "0.0.0.0",
    port = tonumber(port) or M.DEFAULT_REV_PORT,
    accessToken = token or "",
    enable = enable == true,
  }
  M.cfg_save(data)
end

function M.cfg_add_onebot_forward(name, host_addr, port, token, enable)
  local data = M.cfg_load()
  data.connections = data.connections or {}
  data.connections[#data.connections + 1] = {
    id = host.uuid():gsub("-", ""):sub(1, 12),
    name = name,
    type = "onebot",
    mode = "forward",
    host = host_addr or "127.0.0.1",
    port = tonumber(port) or M.DEFAULT_FWD_PORT,
    accessToken = token or "",
    reconnectIntervalMs = 5000,
    enable = enable == true,
  }
  M.cfg_save(data)
end

function M.cfg_add_qq_official(name, app_id, app_secret, sandbox, enable)
  local data = M.cfg_load()
  data.connections = data.connections or {}
  data.connections[#data.connections + 1] = {
    id = host.uuid():gsub("-", ""):sub(1, 12),
    name = name,
    type = "qq_official",
    host = "",
    port = 0,
    appId = app_id or "",
    appSecret = app_secret or "",
    sandbox = sandbox == true,
    enable = enable == true,
  }
  M.cfg_save(data)
end

function M.cfg_delete(idx)
  local data = M.cfg_load()
  local arr = data.connections or {}
  if idx < 0 or idx >= #arr then return false end
  table.remove(arr, idx + 1)
  data.connections = arr
  M.cfg_save(data)
  return true
end

function M.cfg_toggle(idx, enable)
  local data = M.cfg_load()
  local c = data.connections and data.connections[idx + 1]
  if not c then return false end
  c.enable = enable == true
  M.cfg_save(data)
  return true
end

-- ============================================================
-- 安装 / Node / 启停脚本
-- ============================================================

local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M.build_install_script(reinstall)
  local url_lines = { "DOWNLOAD_URLS=(" }
  for _, u in ipairs(M.DOWNLOAD_URLS) do
    url_lines[#url_lines + 1] = "  " .. shell_quote(u)
  end
  url_lines[#url_lines + 1] = ")"
  local force_rm = reinstall and 'rm -rf "' .. M.KAKAKE_HOME .. '"' or ""
  return table.concat({
    "#!/bin/bash",
    "set -e",
    'export TMPDIR="' .. host.tmp_path() .. '"',
    "export DEBIAN_FRONTEND=noninteractive",
    table.concat(url_lines, "\n"),
    'KAKAKE_HOME="' .. M.KAKAKE_HOME .. '"',
    "",
    "progress(){ echo \"$2\" > \"$TMPDIR/kakake_progress_des\"; echo \"$1\" > \"$TMPDIR/kakake_progress\"; echo \"$2\"; }",
    "",
    "progress 1 \"准备依赖 (curl/unzip)...\"",
    "for c in curl unzip; do command -v \"$c\" >/dev/null && continue; apt-get -o Acquire::ForceIPv4=true update; apt-get -o Acquire::ForceIPv4=true install -y curl unzip ca-certificates; break; done",
    "",
    "progress 2 \"下载咔咔珂安装包...\"",
    "ok=0",
    "for u in \"${DOWNLOAD_URLS[@]}\"; do",
    '  [ -n "$u" ] || continue',
    '  echo "尝试: $u"',
    '  if curl -fL --connect-timeout 25 --max-time 300 "$u" -o /tmp/kakake-download.zip; then ok=1; break; fi',
    "done",
    '[ "$ok" -eq 1 ] || { echo "下载 kakake.zip 失败"; exit 1; }',
    "",
    "progress 3 \"解压并部署...\"",
    force_rm,
    "rm -rf /tmp/kakake-extract",
    "mkdir -p /tmp/kakake-extract",
    "unzip -oq /tmp/kakake-download.zip -d /tmp/kakake-extract",
    'if [ -d /tmp/kakake-extract/kakake ]; then mv /tmp/kakake-extract/kakake "$KAKAKE_HOME"',
    'else mv /tmp/kakake-extract "$KAKAKE_HOME"; fi',
    'mkdir -p "$KAKAKE_HOME/data"',
    "rm -f /tmp/kakake-download.zip",
    "rm -rf /tmp/kakake-extract",
    "",
    "progress 4 \"校验安装...\"",
    '[ -f "$KAKAKE_HOME/package.json" ] && [ -f "$KAKAKE_HOME/scripts/bootstrap.mjs" ] || { echo "安装校验失败"; exit 1; }',
    "",
    "progress 5 \"安装完成\"",
  }, "\n")
end

function M.build_node_install_script()
  local ver = M.node_version()
  local mirror = M.node_mirror()
  return table.concat({
    "#!/bin/bash",
    "set -e",
    'export TMPDIR="' .. host.tmp_path() .. '"',
    'NODE_DIR="' .. M.NODE_DIR .. '"',
    'VER="' .. ver .. '"',
    'MIRROR="' .. mirror .. '"',
    'ARCH="arm64"',
    "",
    "progress(){ echo \"$2\" > \"$TMPDIR/kakake_progress_des\"; echo \"$1\" > \"$TMPDIR/kakake_progress\"; echo \"$2\"; }",
    "",
    "progress 1 \"准备 curl/xz...\"",
    "for c in curl xz; do command -v \"$c\" >/dev/null && continue; apt-get -o Acquire::ForceIPv4=true update; apt-get -o Acquire::ForceIPv4=true install -y curl xz-utils; break; done",
    "",
    "progress 2 \"下载 Node.js v${VER}...\"",
    'URL="${MIRROR%/}/v${VER}/node-v${VER}-linux-${ARCH}.tar.xz"',
    'echo "URL: $URL"',
    'curl -fL --retry 3 --connect-timeout 30 -o /tmp/mk-node.tar.xz "$URL"',
    "",
    "progress 3 \"解压 Node.js...\"",
    "rm -rf \"$NODE_DIR\"",
    "mkdir -p \"$NODE_DIR\"",
    'tar -xJf /tmp/mk-node.tar.xz -C "$NODE_DIR" --strip-components=1',
    "rm -f /tmp/mk-node.tar.xz",
    '[ -x "$NODE_DIR/bin/node" ] || { echo "Node 校验失败"; exit 1; }',
    "",
    "progress 4 \"Node.js 安装完成\"",
    'echo "NODE_VER=$("$NODE_DIR/bin/node" -v)"',
  }, "\n")
end

function M.build_node_uninstall_script()
  return table.concat({
    "#!/bin/bash",
    "set -e",
    'rm -rf "' .. M.NODE_DIR .. '"',
    'echo "Node.js 已卸载"',
  }, "\n")
end

function M.build_start_script()
  return table.concat({
    "#!/bin/bash",
    "set -e",
    'KAKAKE_HOME="' .. M.KAKAKE_HOME .. '"',
    'NODE_BIN="' .. M.NODE_BIN .. '"',
    "",
    '[ -f "$KAKAKE_HOME/package.json" ] || { echo "咔咔珂未安装"; exit 1; }',
    '[ -x "$NODE_BIN" ] || { echo "Node.js 未安装, 路径: $NODE_BIN"; exit 1; }',
    'cd "$KAKAKE_HOME" || { echo "无法进入 $KAKAKE_HOME"; exit 1; }',
    'export PATH="$(dirname "$NODE_BIN"):$PATH"',
    'echo ">>> Node $($NODE_BIN -v)"',
    'echo ">>> 启动咔咔珂 (首次可能需安装依赖, 请稍候)..."',
    'exec "$NODE_BIN" scripts/bootstrap.mjs',
  }, "\n")
end

function M.build_stop_script()
  return table.concat({
    "#!/bin/bash",
    'PID_FILE="' .. M.pid_file() .. '"',
    'KAKAKE_HOME="' .. M.KAKAKE_HOME .. '"',
    'if [ -f "$PID_FILE" ]; then',
    '  pid=$(tr -d "[:space:]" < "$PID_FILE")',
    '  [ -n "$pid" ] && kill "$pid" 2>/dev/null || true',
    '  sleep 1',
    '  [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null || true',
    '  rm -f "$PID_FILE"',
    "fi",
    'pkill -f "${KAKAKE_HOME}/scripts/bootstrap.mjs" 2>/dev/null || true',
    'pkill -f "${KAKAKE_HOME}.*tsx src/main.ts" 2>/dev/null || true',
    'sleep 1',
    'echo "咔咔珂已停止"',
  }, "\n")
end

function M.build_uninstall_script()
  local stop_body = M.build_stop_script():gsub("^#!/bin/bash\n", "")
  return table.concat({
    "#!/bin/bash",
    "set -e",
    stop_body,
    'rm -rf "' .. M.KAKAKE_HOME .. '"',
    'rm -f "' .. M.runtime_log() .. '"',
    'echo "咔咔珂已卸载"',
  }, "\n")
end

function M.build_diagnose_script(idx)
  local rows = M.cfg_list()
  local c = rows[idx + 1]
  if not c then return "#!/bin/bash\necho '连接不存在'\nexit 1\n" end
  local r = c.raw
  local mode = r.mode or "reverse"
  local port = r.port or M.DEFAULT_REV_PORT
  local host_addr = r.host or "127.0.0.1"
  return table.concat({
    "#!/bin/bash",
    'LOG="' .. M.runtime_log() .. '"',
    'echo "【连接诊断】' .. (c.name or "") .. '"',
    'if ! pgrep -f "' .. M.KAKAKE_HOME .. '/scripts/bootstrap" >/dev/null 2>&1; then',
    '  echo "咔咔珂未运行, 请先启动"; exit 0',
    "fi",
    'if [ "' .. (r.enable and "1" or "0") .. '" != "1" ]; then',
    '  echo "此连接未启用"; exit 0',
    "fi",
    'if [ "' .. mode .. '" = "reverse" ]; then',
    '  if command -v ss >/dev/null 2>&1 && ss -H -tn state established "( sport = :' .. port .. ' )" 2>/dev/null | grep -q .; then',
    '    echo "正常: NapCat 已连入 ' .. host_addr .. ':' .. port .. '"',
    '  elif ss -tln 2>/dev/null | grep -qE ":' .. port .. '[[:space:]]"; then',
    '    echo "咔咔正在监听 ' .. port .. ', 等待 NapCat WebSocket Client 连入"',
    '    echo "NapCat 侧: WebSocket Client (反向) → ws://127.0.0.1:' .. port .. '"',
    "  else",
    '    echo "咔咔未在端口 ' .. port .. ' 监听, 请重启咔咔"',
    "  fi",
    "else",
    '  if [ "' .. port .. '" = "6700" ]; then',
    '    echo "错误: 6700 是咔咔反向监听口, 正向不应连 6700"',
    '    echo "请改用 OneBot 反向, 或正向连 NapCat 的 3001"',
    '  elif ss -H -tn state established 2>/dev/null | grep -qE "' .. host_addr .. ':' .. port .. '"; then',
    '    echo "正常: 已连上 NapCat ws://' .. host_addr .. ':' .. port .. '"',
    "  else",
    '    echo "未连上 ws://' .. host_addr .. ':' .. port .. '"',
    '    echo "请确认 NapCat 已启动且 WebSocket Server (正向) 端口一致"',
    "  fi",
    "fi",
    'echo "--- 最近日志 ---"',
    'tail -15 "$LOG" 2>/dev/null || true',
  }, "\n")
end

-- ============================================================
-- 任务 UI
-- ============================================================

local function stop_poll()
  if _poll_id then
    host.clear_interval(_poll_id)
    _poll_id = nil
  end
end

local function console_log(key, max_chars)
  max_chars = max_chars or 8000
  local log = host.spawn_log(key) or ""
  if log == "" then return "(等待控制台输出…)" end
  if #log > max_chars then return "…\n" .. log:sub(-max_chars) end
  return log
end

local function progress_des()
  return host.read_file(host.tmp_path() .. "/kakake_progress_des") or ""
end

local function action_wrap(btns)
  return wrap(btns, { spacing = 8, runSpacing = 8 })
end

local function open_log_dialog(key, title)
  title = title or "运行日志"
  local lk = "kakake.log." .. key
  reactive(lk, console_log(key, 50000))
  local vid = host.interval(300, function()
    reactive(lk).set(console_log(key, 50000))
  end)
  host.dialog({
    title = title,
    build = function()
      return card({
        box({ height = 420, child = scroll({
          text("", { bind = lk, size = 11 }),
        }) }),
      })
    end,
    actions = { { label = "关闭", variant = "text", onTap = function() host.clear_interval(vid) end } },
  })
end

local function run_task(opts)
  local key = opts.key
  local title = opts.title or "任务"
  local script = opts.script
  local long_run = opts.long_running == true
  local on_done = opts.on_done
  local kind = opts.kind or "generic"

  stop_poll()
  host.stop(key)
  M.invalidate_cache()

  local phase = state("kakake.task." .. key, "running")
  phase.set("running")
  local msg = reactive("kakake.task.msg." .. key, "准备执行…")
  local logk = "kakake.task.log." .. key
  reactive(logk, "(等待控制台输出…)")

  local function finish(st, text)
    phase.set(st)
    msg.set(text or st)
    stop_poll()
  end

  local function force_cancel()
    finish("cancelled", "已取消")
    host.stop(key)
  end

  local function task_actions()
    return action_wrap({
      button("日志", function() open_log_dialog(key, title) end, { variant = "tonal", icon = "article" }),
      button("强制取消", force_cancel, { variant = "outlined", icon = "cancel" }),
    })
  end

  host.dialog({
    title = title,
    build = function()
      local p = phase.get()
      if p == "ready" then
        if kind == "start" then
          return card("服务已就绪", {
            row({
              chip("运行中", { color = "green" }),
              spacer(8),
              text(msg.get(), { bind = "kakake.task.msg." .. key, size = 13, color = "grey" }),
            }, { cross = "center" }),
            spacer(12),
            action_wrap({
              button("打开面板", function() M.open_admin() end, { variant = "filled", icon = "open_in_browser" }),
              button("日志", function() open_log_dialog(key, title) end, { variant = "tonal", icon = "article" }),
              button("强制取消", force_cancel, { variant = "outlined", icon = "cancel" }),
            }),
          })
        end
        return card("完成", {
          text(msg.get(), { bind = "kakake.task.msg." .. key, size = 14 }),
          spacer(12),
          button("关闭", host.close_dialog, { variant = "text" }),
        })
      end

      if p == "running" then
        return card("任务进行中", {
          row({
            spinner({ size = 22 }),
            spacer(12),
            expanded(text(msg.get(), { bind = "kakake.task.msg." .. key, size = 14 })),
          }, { cross = "center" }),
          spacer(12),
          task_actions(),
        })
      end
      if p == "failed" or p == "stopped" or p == "cancelled" then
        return card("任务结束", {
          text(msg.get(), { bind = "kakake.task.msg." .. key, size = 14, color = "grey" }),
          spacer(12),
          button("关闭", host.close_dialog, { variant = "text" }),
        })
      end
      return card({ text(msg.get(), { bind = "kakake.task.msg." .. key, size = 14 }) })
    end,
    actions = {},
  })

  host.run_ubuntu(script, key, long_run, title, function()
    if phase.get() == "cancelled" then return end
    M.invalidate_cache()
    if kind == "install" then
      if M.installed(true) then finish("ready", "咔咔珂安装完成, 请安装 Node.js 后启动")
      else finish("failed", "安装失败, 请查看日志") end
    elseif kind == "node" then
      local log = host.spawn_log(key) or ""
      local ver = log:match("NODE_VER=(v[%d%.]+)")
      if ver then host.set("kakake_node_installed_ver", ver:sub(2)) end
      if M.node_installed(true) then finish("ready", "Node.js 安装完成: " .. (ver or ""))
      else finish("failed", "Node.js 安装失败") end
    elseif kind == "start" then
      if phase.get() == "ready" then return end
      finish("stopped", "咔咔珂进程已退出, 请查看日志")
    else
      finish("ready", "完成")
    end
  end)

  local ticks = 0
  _poll_id = host.interval(800, function()
    if phase.get() ~= "running" then return end
    ticks = ticks + 1
    reactive(logk).set(console_log(key, 4000))
    local des = progress_des()
    if des ~= "" then msg.set(des) end
    if kind == "start" then
      host.http({
        url = M.admin_url() .. "/",
        timeout = 3,
        on_done = function(res)
          if phase.get() ~= "running" then return end
          local c = res and res.status or 0
          if c == 200 or c == 401 or c == 302 then
            phase.set("ready")
            msg.set("管理面板已就绪: " .. M.admin_url())
          end
        end,
      })
      if not host.spawn_running(key) and ticks > 5 then
        finish("failed", "进程已退出, 请查看终端日志")
      elseif ticks == 8 then
        msg.set("正在启动 (首次运行可能需下载依赖)…")
      end
    end
  end)
end

-- ============================================================
-- 配置 UI
-- ============================================================

function M.open_admin()
  host.webview_open(M.admin_url(), "咔咔珂控制台")
end

function M.show_pairing_hint()
  host.dialog({
    title = "NapCat 对接说明",
    build = function()
      return card({
        text("术语: WebSocket Server=正向(监听)  Client=反向(连出)", { size = 13 }),
        spacer(8),
        text("A. NapCat Client(反向) → ws://127.0.0.1:6700", { size = 13 }),
        text("   [咔咔=Server, NapCat WebSocket Client 连入]", { size = 12, color = "grey" }),
        spacer(4),
        text("B. NapCat Server(正向) ← ws://127.0.0.1:3001", { size = 13 }),
        text("   [咔咔=Client, 连 NapCat WebSocket Server]", { size = 12, color = "grey" }),
        spacer(8),
        text("修改连接配置后需重启咔咔珂。", { size = 12, color = "orange" }),
      })
    end,
    actions = { { label = "关闭", variant = "text" } },
  })
end

function M.open_conn_list_dialog(on_change)
  if not M.installed(true) then
    host.toast("请先安装咔咔珂")
    return
  end
  local rev = reactive("kakake.conn.rev", 0)
  local function rebuild()
    rev.set(rev.get() + 1)
    if on_change then on_change() end
  end
  host.dialog({
    title = "连接配置",
    build = function()
      rev.get()
      local rows = M.cfg_list()
      local items = {
        card({
          text("OneBot 反向/正向 · QQ 官方机器人", { size = 12, color = "grey" }),
          spacer(8),
          action_wrap({
            button("新增连接", function()
              host.close_dialog()
              M.open_conn_add_dialog(function() M.open_conn_list_dialog(on_change) end)
            end, { variant = "filled", icon = "add" }),
            button("对接说明", M.show_pairing_hint, { variant = "tonal", icon = "help_outline" }),
          }),
        }),
      }
      if #rows == 0 then
        items[#items + 1] = card({ text("暂无连接, 点「新增连接」添加", { size = 13, color = "grey" }) })
      end
      for _, r in ipairs(rows) do
        local st = r.enable and "已启用" or "未启用"
        items[#items + 1] = tile(r.name, {
          subtitle = r.addr .. " · " .. st,
          icon = r.enable and "link" or "link_off",
          onTap = function()
            host.close_dialog()
            M.open_conn_detail_dialog(r.idx, function() M.open_conn_list_dialog(on_change) end)
          end,
        })
      end
      return box({ height = 420, child = scroll({ column(items) }) })
    end,
    actions = { { label = "关闭", variant = "text", onTap = rebuild } },
  })
end

function M.open_conn_add_dialog(on_back)
  host.dialog({
    title = "新增连接",
    build = function()
      return card({
        tile("OneBot 反向 (咔咔=Server)", {
          subtitle = "NapCat WebSocket Client → 6700",
          icon = "south_west",
          onTap = function()
            host.close_dialog()
            M.open_conn_form_reverse(on_back)
          end,
        }),
        tile("OneBot 正向 (咔咔=Client)", {
          subtitle = "连 NapCat WebSocket Server → 3001",
          icon = "north_east",
          onTap = function()
            host.close_dialog()
            M.open_conn_form_forward(on_back)
          end,
        }),
        tile("QQ 官方机器人", {
          subtitle = "AppID + AppSecret",
          icon = "smart_toy_outlined",
          onTap = function()
            host.close_dialog()
            M.open_conn_form_qq(on_back)
          end,
        }),
      })
    end,
    actions = { { label = "返回", variant = "text", onTap = function()
      host.close_dialog()
      if on_back then on_back() end
    end } },
  })
end

function M.open_conn_form_reverse(on_back)
  local name_st = state("kakake.form.rev.name", "NapCat 默认接入")
  local host_st = state("kakake.form.rev.host", "0.0.0.0")
  local port_st = state("kakake.form.rev.port", tostring(M.DEFAULT_REV_PORT))
  local token_st = state("kakake.form.rev.token", "")
  host.dialog({
    title = "OneBot 反向",
    build = function()
      return card({
        textfield({ label = "名称", value = name_st.get(), onChanged = function(v) name_st.set(v) end }),
        textfield({ label = "监听地址", hint = "0.0.0.0", value = host_st.get(), onChanged = function(v) host_st.set(v) end }),
        textfield({ label = "监听端口", hint = "6700", value = port_st.get(), onChanged = function(v) port_st.set(v) end }),
        textfield({ label = "Access Token", value = token_st.get(), onChanged = function(v) token_st.set(v) end }),
        spacer(8),
        button("保存并启用", function()
          M.cfg_add_onebot_reverse(name_st.get(), host_st.get(), port_st.get(), token_st.get(), true)
          host.close_dialog()
          host.toast("已添加反向连接")
          if on_back then on_back() end
        end, { variant = "filled", icon = "save" }),
      })
    end,
    actions = { { label = "取消", variant = "text" } },
  })
end

function M.open_conn_form_forward(on_back)
  local name_st = state("kakake.form.fwd.name", "NapCat 正向")
  local host_st = state("kakake.form.fwd.host", "127.0.0.1")
  local port_st = state("kakake.form.fwd.port", tostring(M.DEFAULT_FWD_PORT))
  local token_st = state("kakake.form.fwd.token", "")
  host.dialog({
    title = "OneBot 正向",
    build = function()
      return card({
        textfield({ label = "名称", value = name_st.get(), onChanged = function(v) name_st.set(v) end }),
        textfield({ label = "NapCat 地址", hint = "127.0.0.1", value = host_st.get(), onChanged = function(v) host_st.set(v) end }),
        textfield({ label = "NapCat WS 端口", hint = "3001", value = port_st.get(), onChanged = function(v) port_st.set(v) end }),
        textfield({ label = "Access Token", value = token_st.get(), onChanged = function(v) token_st.set(v) end }),
        spacer(8),
        text("勿将正向端口设为 6700 (那是咔咔反向监听口)", { size = 12, color = "orange" }),
        spacer(8),
        button("保存并启用", function()
          local p = tonumber(port_st.get()) or M.DEFAULT_FWD_PORT
          if p == 6700 then
            host.toast("正向端口不能为 6700")
            return
          end
          M.cfg_add_onebot_forward(name_st.get(), host_st.get(), port_st.get(), token_st.get(), true)
          host.close_dialog()
          host.toast("已添加正向连接")
          if on_back then on_back() end
        end, { variant = "filled", icon = "save" }),
      })
    end,
    actions = { { label = "取消", variant = "text" } },
  })
end

function M.open_conn_form_qq(on_back)
  local name_st = state("kakake.form.qq.name", "QQ官方")
  local app_st = state("kakake.form.qq.app", "")
  local sec_st = state("kakake.form.qq.sec", "")
  host.dialog({
    title = "QQ 官方机器人",
    build = function()
      return card({
        textfield({ label = "名称", value = name_st.get(), onChanged = function(v) name_st.set(v) end }),
        textfield({ label = "AppID", value = app_st.get(), onChanged = function(v) app_st.set(v) end }),
        textfield({ label = "AppSecret", value = sec_st.get(), onChanged = function(v) sec_st.set(v) end }),
        spacer(8),
        button("保存并启用 (正式环境)", function()
          M.cfg_add_qq_official(name_st.get(), app_st.get(), sec_st.get(), false, true)
          host.close_dialog()
          host.toast("已添加 QQ 官方连接")
          if on_back then on_back() end
        end, { variant = "filled", icon = "save" }),
      })
    end,
    actions = { { label = "取消", variant = "text" } },
  })
end

function M.open_conn_detail_dialog(idx, on_back)
  local rows = M.cfg_list()
  local r = rows[idx + 1]
  if not r then host.toast("连接不存在"); return end
  host.dialog({
    title = r.name,
    build = function()
      return card({
        text("类型: " .. r.category, { size = 13 }),
        text("地址: " .. r.addr, { size = 13 }),
        text("状态: " .. (r.enable and "已启用" or "未启用"), { size = 13 }),
        spacer(12),
        action_wrap({
          button(r.enable and "禁用" or "启用", function()
            M.cfg_toggle(idx, not r.enable)
            host.close_dialog()
            host.toast("已更新")
            if on_back then on_back() end
          end, { variant = "tonal", icon = "toggle_on" }),
          button("诊断", function()
            host.close_dialog()
            run_task({
              key = "kakake_diag_" .. idx,
              title = "连接诊断",
              script = M.build_diagnose_script(idx),
              kind = "diag",
            })
          end, { variant = "tonal", icon = "troubleshoot" }),
          button("删除", function()
            host.confirm("确认删除此连接?", function(yes)
              if yes then
                M.cfg_delete(idx)
                host.close_dialog()
                host.toast("已删除")
                if on_back then on_back() end
              end
            end, { title = "删除连接" })
          end, { variant = "outlined", icon = "delete" }),
        }),
      })
    end,
    actions = { { label = "返回", variant = "text", onTap = function()
      host.close_dialog()
      if on_back then on_back() end
    end } },
  })
end

function M.open_node_version_dialog()
  local cur = M.node_version()
  host.dialog({
    title = "Node.js 版本",
    build = function()
      local rows = {}
      for _, v in ipairs(M.NODE_VERSIONS) do
        local sel = cur == v.value
        rows[#rows + 1] = tile(v.label, {
          icon = sel and "radio_button_checked" or "radio_button_unchecked",
          onTap = function()
            host.set("kakake_node_version", v.value)
            host.close_dialog()
            host.toast("已选择 " .. v.label)
          end,
        })
      end
      return box({ height = 240, child = scroll({ column(rows) }) })
    end,
    actions = { { label = "关闭", variant = "text" } },
  })
end

function M.open_node_mirror_dialog()
  local cur = M.node_mirror()
  host.dialog({
    title = "Node.js 下载镜像",
    build = function()
      local rows = {}
      for _, m in ipairs(M.NODE_MIRRORS) do
        local sel = cur == m.value
        rows[#rows + 1] = tile(m.label, {
          icon = sel and "radio_button_checked" or "radio_button_unchecked",
          onTap = function()
            host.set("kakake_node_mirror", m.value)
            host.close_dialog()
            host.toast("已选择 " .. m.label)
          end,
        })
      end
      return box({ height = 320, child = scroll({ column(rows) }) })
    end,
    actions = { { label = "关闭", variant = "text" } },
  })
end

-- ============================================================
-- 公开 API
-- ============================================================

function M.install(reinstall)
  run_task({
    key = M.INSTALL_KEY,
    title = "安装咔咔珂",
    kind = "install",
    script = M.build_install_script(reinstall),
  })
end

function M.install_node()
  run_task({
    key = M.NODE_INSTALL_KEY,
    title = "安装 Node.js",
    kind = "node",
    script = M.build_node_install_script(),
  })
end

function M.uninstall_node()
  if M.is_running() then
    host.toast("请先停止咔咔珂")
    return
  end
  host.confirm("确认卸载 Node.js?", function(yes)
    if not yes then return end
    run_task({
      key = "kakake_node_rm",
      title = "卸载 Node.js",
      script = M.build_node_uninstall_script(),
    })
  end)
end

function M.start()
  if not M.installed(true) then
    host.confirm("咔咔珂尚未安装, 是否现在安装?", function(yes)
      if yes then M.install(false) end
    end, { title = "未安装", ok_text = "安装" })
    return
  end
  if not M.node_installed(true) then
    host.confirm("Node.js 尚未安装, 是否现在安装?", function(yes)
      if yes then M.install_node() end
    end, { title = "需要 Node.js", ok_text = "安装" })
    return
  end
  if host.spawn_running(M.SPAWN_KEY) then
    host.toast("咔咔珂已在运行")
    M.open_admin()
    return
  end
  run_task({
    key = M.SPAWN_KEY,
    title = "启动咔咔珂",
    kind = "start",
    long_running = true,
    script = M.build_start_script(),
  })
end

function M.stop()
  stop_poll()
  host.stop(M.SPAWN_KEY)
  host.run_ubuntu(M.build_stop_script(), "kakake_stop", false, "停止咔咔珂", function()
    host.toast("已停止咔咔珂")
  end)
end

function M.restart()
  M.stop()
  host.delay(800, function() M.start() end)
end

function M.uninstall()
  host.confirm("确认彻底卸载咔咔珂? 将删除 ~/kakake", function(yes)
    if not yes then return end
    M.stop()
    host.delay(500, function()
      run_task({
        key = "kakake_uninstall",
        title = "卸载咔咔珂",
        script = M.build_uninstall_script(),
      })
    end)
  end, { title = "卸载咔咔珂", ok_text = "卸载" })
end

return M
