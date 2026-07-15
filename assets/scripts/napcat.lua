-- napcat.lua · NapCatQQ 引擎 (Ubuntu 容器内安装 / 启停 / WebUI)

local M = {}

M.SPAWN_KEY = "napcat"
M.INSTALL_KEY = "napcat_install"
M.INSTALL_STEPS = 7
M.DEFAULT_WEBUI_PORT = 6099
M.DEFAULT_INSTALL_DIR = "/root/Napcat"
M.MARKER = "/root/.napcat/install_path"

local _installed_cache = nil
local _installed_checked_at = 0
local _dir_cache = nil
local CACHE_MS = 30000
local _poll_id = nil

-- ============================================================
-- 路径 / 状态
-- ============================================================

local function ub(path)
  if not path or path == "" then return host.ubuntu_path() end
  if path:sub(1, 1) == "/" then return host.ubuntu_path() .. path end
  return host.ubuntu_path() .. "/" .. path
end

local function marker_host_path()
  return ub(M.MARKER)
end

function M.install_dir()
  if _dir_cache then return _dir_cache end
  local custom = host.get("napcat_install_dir")
  if custom and custom ~= "" then
    _dir_cache = custom
    return custom
  end
  local ok, m = pcall(function() return host.read_file(marker_host_path()) end)
  if ok and m then
    m = m:match("^%s*(.-)%s*$")
    if m and m ~= "" then
      _dir_cache = m
      return m
    end
  end
  _dir_cache = M.DEFAULT_INSTALL_DIR
  return M.DEFAULT_INSTALL_DIR
end

function M.webui_port()
  local p = tonumber(host.get("napcat_webui_port"))
  return p or M.DEFAULT_WEBUI_PORT
end

function M.webui_url()
  return "http://127.0.0.1:" .. M.webui_port()
end

function M.invalidate_cache()
  _installed_cache = nil
  _installed_checked_at = 0
  _dir_cache = nil
end

local ROOTLESS_CANDIDATES = {
  "/root/Napcat", "/opt/napcat", "/root/napcat", "/root/NapCat",
}

local function qq_binary(base)
  return base .. "/opt/QQ/qq"
end

function M.installed(force)
  local now = host.now_ms()
  if not force and _installed_cache ~= nil and (now - _installed_checked_at) < CACHE_MS then
    return _installed_cache
  end
  local ok, result = pcall(function()
    if host.exists(marker_host_path()) then return true end
    local d = M.install_dir()
    if d and host.exists(ub(qq_binary(d))) then return true end
    if d and host.exists(ub(d .. "/napcat.js")) then return true end
    for _, c in ipairs(ROOTLESS_CANDIDATES) do
      if host.exists(ub(qq_binary(c))) or host.exists(ub(c .. "/napcat.js")) then
        return true
      end
    end
    return false
  end)
  _installed_cache = ok and result == true
  _installed_checked_at = now
  return _installed_cache
end

function M.is_running(ctx)
  if not ctx or not ctx.running then return false end
  return ctx.running[M.SPAWN_KEY] == true
end

-- ============================================================
-- 镜像 / 安装 URL
-- ============================================================

M.INSTALL_URL_NCLATEST =
  "https://nclatest.znin.net/NapNeko/NapCat-Installer/main/script/install.sh"
M.INSTALL_URL_GITHUB =
  "https://raw.githubusercontent.com/NapNeko/NapCat-Installer/main/script/install.sh"

M.MIRROR_SOURCES = {
  { label = "直连 nclatest (官方, 推荐)", value = "nclatest" },
  { label = "直连 GitHub Raw",            value = "github_raw" },
  { label = "Ghfast → GitHub Raw",        value = "gh:https://ghfast.top" },
  { label = "Gh-Proxy → GitHub Raw",      value = "gh:https://gh-proxy.com" },
  { label = "GhProxyNet → GitHub Raw",    value = "gh:https://ghproxy.net" },
  { label = "GhProxyCc → GitHub Raw",     value = "gh:https://ghproxy.cc" },
}

function M.download_proxy()
  return host.get("napcat_download_proxy") or "nclatest"
end

function M.download_proxy_label()
  local v = M.download_proxy()
  for _, s in ipairs(M.MIRROR_SOURCES) do
    if s.value == v then return s.label end
  end
  return v
end

function M.build_install_urls()
  local v = M.download_proxy()
  if v == "nclatest" then
    return { M.INSTALL_URL_NCLATEST, M.INSTALL_URL_GITHUB }
  end
  if v == "github_raw" then
    return { M.INSTALL_URL_GITHUB, M.INSTALL_URL_NCLATEST }
  end
  if v:sub(1, 3) == "gh:" then
    local prefix = v:sub(4)
    return {
      prefix .. "/" .. M.INSTALL_URL_GITHUB,
      M.INSTALL_URL_GITHUB,
      M.INSTALL_URL_NCLATEST,
    }
  end
  return { M.INSTALL_URL_NCLATEST, M.INSTALL_URL_GITHUB }
end

local function gh_proxy_idx()
  local p = M.download_proxy()
  if p:sub(1, 3) == "gh:" then return "1" end
  return "0"
end

-- ============================================================
-- WebUI / 二维码
-- ============================================================

function M.qrcode_path()
  local d = M.install_dir()
  return ub(d .. "/opt/QQ/resources/app/app_launcher/napcat/cache/qrcode.png")
end

local _qr_src_b64 = nil

function M.qrcode_display_path()
  return host.tmp_path() .. "/napcat_qr_display.png"
end

function M.reset_qrcode_cache()
  _qr_src_b64 = nil
  reactive("napcat.qr.rev", 0)
end

--- 源文件任意字节变化即复制到独立展示路径并 bump rev, 供 image bind 刷新
function M.sync_qrcode()
  local src = M.qrcode_path()
  if not host.exists(src) then
    _qr_src_b64 = nil
    return false
  end
  local b64 = host.read_bytes(src)
  if not b64 or b64 == "" then return false end
  if b64 == _qr_src_b64 then return false end
  _qr_src_b64 = b64
  local dst = M.qrcode_display_path()
  if not host.write_bytes(dst, b64) then return false end
  local rev = reactive("napcat.qr.rev")
  rev.set((tonumber(rev.get()) or 0) + 1)
  return true
end

--- 忽略缓存, 强制从源文件重新加载二维码
function M.force_refresh_qrcode()
  _qr_src_b64 = nil
  return M.sync_qrcode()
end

function M.webui_config_path()
  local d = M.install_dir()
  return ub(d .. "/opt/QQ/resources/app/app_launcher/napcat/config/webui.json")
end

function M.webui_token()
  local raw = host.read_file(M.webui_config_path())
  if not raw or raw == "" then return nil end
  local ok, cfg = pcall(json.decode, raw)
  if ok and cfg and cfg.token and cfg.token ~= "" then return cfg.token end
  return nil
end

function M.webui_panel_url()
  local token = M.webui_token()
  if token then
    return M.webui_url() .. "/webui?token=" .. token
  end
  return M.webui_url()
end

function M.open_webui_panel()
  host.webview_open(M.webui_panel_url(), "NapCat 面板")
end

function M.open_webui(_)
  M.open_webui_panel()
end

-- ============================================================
-- 启动脚本: 与手动在 Ubuntu 终端输入完全一致
-- ============================================================

function M.start_command()
  local dir = M.install_dir()
  return "xvfb-run -a " .. dir .. "/opt/QQ/qq --no-sandbox"
end

function M.build_start_script()
  local dir = M.install_dir()
  local port = M.webui_port()
  return table.concat({
    "#!/bin/bash",
    "set -e",
    "export DEBIAN_FRONTEND=noninteractive",
    "export NAPCAT_WEBUI_PREFERRED_PORT=" .. port,
    "export NAPCAT_DISABLE_BYPASS=0",
    'DIR="' .. dir .. '"',
    'if [ -f /root/.napcat/install_path ]; then',
    '  DIR=$(tr -d "\\r\\n" < /root/.napcat/install_path)',
    "fi",
    'QQ="$DIR/opt/QQ/qq"',
    'if [ ! -f "$QQ" ]; then',
    '  echo "错误: 找不到 $QQ, 请先安装 NapCat"',
    "  exit 1",
    "fi",
    "if ! command -v xvfb-run >/dev/null 2>&1; then",
    '  echo "安装 xvfb..."',
    "  apt-get -o Acquire::ForceIPv4=true update",
    "  apt-get -o Acquire::ForceIPv4=true install -y xvfb xauth",
    "fi",
    'echo ">>> exec xvfb-run -a $QQ --no-sandbox"',
    'exec xvfb-run -a "$QQ" --no-sandbox',
  }, "\n")
end

function M.build_napcat_zip_urls(version)
  local base = "https://github.com/NapNeko/NapCatQQ/releases/download/v"
    .. version .. "/NapCat.Shell.zip"
  local v = M.download_proxy()
  if v:sub(1, 3) == "gh:" then
    local prefix = v:sub(4)
    return { prefix .. "/" .. base, base }
  end
  return { base }
end

M.NAPCAT_VERSIONS = {
  { label = "最新版",  value = "latest" },
  { label = "4.18.9",  value = "4.18.9" },
  { label = "4.18.5",  value = "4.18.5" },
  { label = "4.18.0",  value = "4.18.0" },
  { label = "4.17.53", value = "4.17.53" },
  { label = "4.17.23", value = "4.17.23" },
  { label = "4.17.0",  value = "4.17.0" },
  { label = "4.15.0",  value = "4.15.0" },
}

-- ============================================================
-- 安装脚本 (扁平 bash, 写入 ubuntu job 执行)
-- ============================================================

local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

function M.build_install_script(reinstall, version)
  version = version or "latest"
  local urls = M.build_install_urls()
  local url_lines = { "INSTALL_URLS=(" }
  for _, u in ipairs(urls) do
    url_lines[#url_lines + 1] = "  " .. shell_quote(u)
  end
  url_lines[#url_lines + 1] = ")"
  local force = reinstall and "--force" or ""
  local proxy = gh_proxy_idx()
  local work_dir = host.tmp_path() .. "/napcat-work"

  local pre_zip = {}
  if version ~= "latest" then
    local zip_urls = M.build_napcat_zip_urls(version)
    pre_zip[#pre_zip + 1] = "NAPCAT_ZIP_URLS=("
    for _, u in ipairs(zip_urls) do
      pre_zip[#pre_zip + 1] = "  " .. shell_quote(u)
    end
    pre_zip[#pre_zip + 1] = ")"
    pre_zip[#pre_zip + 1] = 'progress 3 "下载 NapCat v' .. version .. '..."'
    pre_zip[#pre_zip + 1] = "zip_ok=0"
    pre_zip[#pre_zip + 1] = 'for u in "${NAPCAT_ZIP_URLS[@]}"; do'
    pre_zip[#pre_zip + 1] = '  [ -n "$u" ] || continue'
    pre_zip[#pre_zip + 1] = '  echo "尝试: $u"'
    pre_zip[#pre_zip + 1] = '  if curl -fL --connect-timeout 25 --max-time 300 "$u" -o NapCat.Shell.zip; then zip_ok=1; break; fi'
    pre_zip[#pre_zip + 1] = "done"
    pre_zip[#pre_zip + 1] = '[ "$zip_ok" -eq 1 ] || { echo "下载 NapCat v' .. version .. ' 失败"; exit 1; }'
  end

  return table.concat({
    "#!/bin/bash",
    "set -e",
    'export TMPDIR="' .. host.tmp_path() .. '"',
    "export DEBIAN_FRONTEND=noninteractive",
    table.concat(url_lines, "\n"),
    'MARKER="' .. M.MARKER .. '"',
    "PROXY_IDX=" .. proxy,
    "FORCE_FLAG=" .. shell_quote(force),
    'WORK="' .. work_dir .. '"',
    "",
    "progress(){ echo \"$2\" > \"$TMPDIR/napcat_progress_des\"; echo \"$1\" > \"$TMPDIR/napcat_progress\"; echo \"$2\"; }",
    "",
    "repair_apt_dpkg(){ dpkg --configure -a || true; }",
    "",
    "progress 1 \"修复包管理器...\"",
    "repair_apt_dpkg",
    "",
    "progress 2 \"准备 curl/sudo...\"",
    "for c in curl sudo; do command -v \"$c\" >/dev/null && continue; apt-get -o Acquire::ForceIPv4=true update; apt-get -o Acquire::ForceIPv4=true install -y sudo git curl ca-certificates; break; done",
    "",
    'rm -rf "$WORK"',
    'mkdir -p "$WORK"',
    'cd "$WORK"',
    table.concat(pre_zip, "\n"),
    "",
    "progress 4 \"下载 install.sh...\"",
    "ok=0",
    "for u in \"${INSTALL_URLS[@]}\"; do",
    '  [ -n "$u" ] || continue',
    '  echo "尝试: $u"',
    '  if curl -fL --connect-timeout 25 --max-time 180 "$u" -o /tmp/napcat-install.sh; then',
    '    if head -n 5 /tmp/napcat-install.sh | grep -qiE "<!doctype|<html"; then',
    '      echo "非脚本, 换镜像"; continue',
    "    fi",
    "    ok=1; break",
    "  fi",
    "done",
    '[ "$ok" -eq 1 ] || { echo "下载 install.sh 失败"; exit 1; }',
    "",
    "progress 5 \"执行官方安装 (apt+QQ, 约 5-15 分钟)...\"",
    "chmod +x /tmp/napcat-install.sh",
    'bash /tmp/napcat-install.sh --docker n --cli n --proxy "$PROXY_IDX" $FORCE_FLAG',
    "",
    "progress 6 \"检测安装目录...\"",
    'mkdir -p "$(dirname "$MARKER")"',
    'for d in "$HOME/Napcat" /root/Napcat; do',
    '  if [ -f "$d/opt/QQ/qq" ]; then echo "$d" > "$MARKER"; echo "安装目录: $d"; break; fi',
    "done",
    "",
    "progress 7 \"安装完成\"",
  }, "\n")
end

-- ============================================================
-- 任务 UI: 后台 ubuntu job + 实时控制台日志
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
  return host.read_file(host.tmp_path() .. "/napcat_progress_des") or ""
end

--- 画廊同款: 按钮组用 wrap 排布
local function action_wrap(btns)
  return wrap(btns, { spacing = 8, runSpacing = 8 })
end

local function qr_viewport()
  if host.exists(M.qrcode_display_path()) then
    return center(clip(image(M.qrcode_display_path(), {
      width = 220,
      height = 220,
      bind = "napcat.qr.rev",
    }), { radius = 14 }))
  end
  return center(box({
    width = 220,
    height = 220,
    child = center(spinner({ size = 28 })),
    style = { bg = "indigo", radius = 14, shadow = { color = "#33000000", blur = 8, dy = 3 } },
  }))
end

local function show_token_dialog()
  local token = M.webui_token() or "(尚未生成)"
  host.dialog({
    title = "WebUI 密钥",
    build = function()
      return card("访问凭证", {
        text("Token", { size = 12, color = "grey" }),
        text(token, { size = 14, weight = "bold" }),
        spacer(8),
        text("面板地址", { size = 12, color = "grey" }),
        text(M.webui_panel_url(), { size = 13 }),
        spacer(12),
        action_wrap({
          button("复制 Token", function()
            if token:sub(1, 1) ~= "(" then
              host.clipboard.copy(token)
              host.toast("已复制")
            end
          end, { variant = "tonal", icon = "content_copy" }),
          button("打开面板", M.open_webui_panel, { variant = "filled", icon = "open_in_browser" }),
        }),
      })
    end,
    actions = { { label = "关闭", variant = "text" } },
  })
end

local function open_log_dialog(key, title)
  title = title or "运行日志"
  local lk = "napcat.log." .. key
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

--- 通用任务弹窗: run ubuntu 扁平脚本, 不跳转页面, 日志来自终端 PTY
local function run_task(opts)
  local key = opts.key
  local title = opts.title or "任务"
  local script = opts.script
  local long_run = opts.long_running == true
  local on_done = opts.on_done

  stop_poll()
  host.stop(key)
  M.reset_qrcode_cache()

  local phase = state("napcat.task." .. key, "running")
  phase.set("running")
  local msg = reactive("napcat.task.msg." .. key, "准备执行…")
  local logk = "napcat.task.log." .. key
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

  local function task_actions(extra)
    local btns = extra or {}
    btns[#btns + 1] = button("日志", function() open_log_dialog(key, title) end, { variant = "tonal", icon = "article" })
    btns[#btns + 1] = button("强制取消", force_cancel, { variant = "outlined", icon = "cancel" })
    return action_wrap(btns)
  end

  host.dialog({
    title = title,
    build = function()
      local p = phase.get()

      if opts.kind == "start" and (p == "running" or p == "qr") then
        return card("扫码登录", {
          qr_viewport(),
          spacer(12),
          action_wrap({
            button("刷新二维码", function()
              if M.force_refresh_qrcode() then
                host.toast("二维码已刷新")
              elseif host.exists(M.qrcode_path()) then
                host.toast("二维码无变化")
              else
                host.toast("尚未生成二维码")
              end
            end, { variant = "tonal", icon = "refresh" }),
            button("日志", function() open_log_dialog(key, title) end, { variant = "tonal", icon = "article" }),
            button("强制取消", force_cancel, { variant = "outlined", icon = "cancel" }),
          }),
        })
      end

      if p == "running" then
        return card("任务进行中", {
          row({
            spinner({ size = 22 }),
            spacer(12),
            expanded(text(msg.get(), { bind = "napcat.task.msg." .. key, size = 14 })),
          }, { cross = "center" }),
          spacer(12),
          task_actions(),
        })
      end

      if p == "ready" then
        return card("服务已就绪", {
          row({
            chip("运行中", { color = "green" }),
            spacer(8),
            text("WebUI 与 OneBot 接口可用", { size = 13, color = "grey" }),
          }, { cross = "center" }),
          spacer(12),
          action_wrap({
            button("查看密钥", show_token_dialog, { variant = "tonal", icon = "vpn_key" }),
            button("登录面板", M.open_webui_panel, { variant = "filled", icon = "login" }),
            button("关闭", host.close_dialog, { variant = "text" }),
          }),
        })
      end

      if p == "failed" or p == "stopped" or p == "cancelled" then
        return card("任务结束", {
          text(msg.get(), { bind = "napcat.task.msg." .. key, size = 14, color = "grey" }),
          spacer(12),
          button("关闭", host.close_dialog, { variant = "text" }),
        })
      end

      return card({ text(msg.get(), { bind = "napcat.task.msg." .. key, size = 14 }) })
    end,
    actions = {},
  })

  host.run_ubuntu(script, key, long_run, title, function()
    if phase.get() == "cancelled" then return end
    if opts.kind == "install" then
      M.invalidate_cache()
      if M.installed(true) then finish("ready", "安装完成")
      else finish("failed", "安装失败") end
    elseif opts.kind == "start" then
      if phase.get() == "ready" then return end
      finish("stopped", "进程已退出")
    else
      finish("stopped", "完成")
    end
  end)

  local ticks = 0
  local webui_hits = 0
  _poll_id = host.interval(800, function()
    local p = phase.get()
    if p ~= "running" and p ~= "qr" then return end

    ticks = ticks + 1
    reactive(logk).set(console_log(key, 4000))

    local des = progress_des()
    if des ~= "" then msg.set(des) end

    if opts.kind == "start" then
      if p == "qr" and not host.exists(M.qrcode_path()) then
        finish("ready", "登录成功")
        return
      end
      if host.exists(M.qrcode_path()) then
        M.sync_qrcode()
        phase.set("qr")
        msg.set("请扫码登录 QQ")
        return
      end
      host.http({
        url = M.webui_url() .. "/",
        timeout = 3,
        on_done = function(res)
          local c = res and res.status or 0
          if c == 200 or c == 401 or c == 302 then
            webui_hits = webui_hits + 1
            if webui_hits >= 2 and phase.get() ~= "qr" then
              finish("ready", "NapCat 已就绪")
            else
              msg.set("WebUI 响应中…")
            end
          end
        end,
      })
      if not host.spawn_running(key) and ticks > 15 then
        finish("failed", "进程已退出, 请查看日志")
      end
    end
  end)
end

-- ============================================================
-- 公开 API
-- ============================================================

function M.install(reinstall, version)
  version = version or "latest"
  local ver_label = version == "latest" and "最新版" or ("v" .. version)
  run_task({
    key = M.INSTALL_KEY,
    title = "安装 NapCat (" .. ver_label .. ")",
    kind = "install",
    long_running = false,
    cmd_hint = "bash NapCat-Installer/install.sh",
    script = M.build_install_script(reinstall, version),
  })
end

function M.open_install_version_dialog(reinstall)
  host.dialog({
    title = "选择 NapCat 版本",
    build = function()
      local rows = {
        card({
          text("指定版本将预下载对应 NapCat.Shell.zip; 选「最新版」则由官方脚本拉取 latest。",
            { size = 12, color = "grey" }),
        }),
      }
      for _, v in ipairs(M.NAPCAT_VERSIONS) do
        rows[#rows + 1] = tile(v.label, {
          icon = "tag",
          onTap = function()
            host.close_dialog()
            host.set("napcat_install_version", v.value)
            M.install(reinstall, v.value)
          end,
        })
      end
      return box({ height = 420, child = scroll({ column(rows) }) })
    end,
    actions = { { label = "取消", variant = "text" } },
  })
end

function M.prompt_install(reinstall)
  M.open_install_version_dialog(reinstall)
end

function M.start(_)
  if not M.installed(true) then
    host.confirm("NapCat 尚未安装。是否现在安装?", function(yes)
      if yes then M.prompt_install(false) end
    end, { title = "未安装", ok_text = "安装", cancel_text = "取消" })
    return
  end
  if host.spawn_running(M.SPAWN_KEY) then
    host.toast("NapCat 已在运行")
    return
  end
  run_task({
    key = M.SPAWN_KEY,
    title = "启动 NapCat",
    kind = "start",
    long_running = true,
    cmd_hint = M.start_command(),
    script = M.build_start_script(),
  })
end

function M.stop()
  stop_poll()
  host.stop(M.SPAWN_KEY)
  host.toast("已停止 NapCat")
end

function M.restart()
  M.stop()
  host.delay(600, function() M.start(false) end)
end

function M.rescan_install()
  M.invalidate_cache()
  local script = table.concat({
    "#!/bin/bash",
    'MARKER="' .. M.MARKER .. '"',
    'for d in /root/Napcat "$HOME/Napcat"; do',
    '  [ -f "$d/opt/QQ/qq" ] && { mkdir -p "$(dirname "$MARKER")"; echo "$d" > "$MARKER"; echo "OK: $d"; exit 0; }',
    "done",
    'echo "未找到"; exit 1',
  }, "\n")
  host.run_ubuntu(script, "napcat_rescan", false, "NapCat 检测", function()
    M.invalidate_cache()
    host.toast("检测完成")
  end)
end

function M.repair_dpkg()
  host.run_ubuntu("#!/bin/bash\nexport DEBIAN_FRONTEND=noninteractive\ndpkg --configure -a\n",
    "napcat_repair", false, "修复 apt/dpkg", function()
    host.toast("dpkg 修复完成")
  end)
end

function M.wait_webui(tries)
  tries = tries or 0
  if tries > 40 then host.toast("WebUI 未就绪"); return end
  host.http({
    url = M.webui_url() .. "/",
    timeout = 4,
    on_done = function(res)
      if res and (res.status == 200 or res.status == 401 or res.status == 302) then
        M.open_webui_panel()
      else
        host.delay(1000, function() M.wait_webui(tries + 1) end)
      end
    end,
    on_error = function()
      host.delay(1000, function() M.wait_webui(tries + 1) end)
    end,
  })
end

return M
