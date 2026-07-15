-- MK-BOT · 默认皮肤 (main.lua)
--
-- 导航、页面与顶栏均由 Lua 声明式定义; 改脚本即改 App。
-- NapCat / Kakake 机器人管理 · Ubuntu 容器 · 内嵌 Web 浏览器

-- 导航页索引 (host.nav.go 用)
local TAB = { home = 0, webui = 1, napcat = 2, kakake = 3, terminal = 4 }

nav.tabs({
  { title = "主页",  icon = "home_outlined",          page = "home" },
  { title = "Web",   icon = "language",                page = webview() },
  { title = "NapCat", icon = "pets_outlined",          page = "napcat" },
  { title = "Kakake", icon = "smart_toy_outlined",     page = "kakake" },
  { title = "终端",  icon = "terminal",                page = terminal() },
})

-- ============================================================
-- opencode / Ubuntu 环境安装 (沙盒自带 Agent 能力所需)
-- 三步: 基础命令 (sudo/git/curl) / uv / opencode
-- ============================================================
local GH_PROXIES = {
  { label = "直连 (GitHub 原始)", value = "direct" },
  { label = "Ghfast",     value = "https://ghfast.top" },
  { label = "Gh-Proxy",   value = "https://gh-proxy.com" },
  { label = "GhProxyNet", value = "https://ghproxy.net" },
  { label = "GhProxyCc",  value = "https://ghproxy.cc" },
  { label = "Dpik",       value = "https://gh.dpik.top" },
  { label = "Monlor",     value = "https://gh.monlor.com" },
  { label = "Chjina",     value = "https://gh.chjina.com" },
  { label = "BokiMoe",    value = "https://github.boki.moe" },
  { label = "JasonZeng",  value = "https://gh.jasonzeng.dev" },
  { label = "GeekerTao",  value = "https://gh.geekertao.top" },
  { label = "Nxnow",      value = "https://gh.nxnow.top" },
  { label = "Npee",       value = "https://down.npee.cn" },
}
local function gh_proxy() return host.get("environment_github_proxy") or "direct" end
local function gh_proxy_label(v)
  for _, p in ipairs(GH_PROXIES) do if p.value == v then return p.label end end
  return v
end

-- 镜像测速 (纯 Lua 端): value -> { ms=数字 | err=字符串 | testing=true }
local gh_speed = {}
local GH_TEST_PATH = "/https://raw.githubusercontent.com/astral-sh/uv/main/README.md"
local function gh_test_all()
  local rev = state("gh.speed.rev", 0)
  for _, p in ipairs(GH_PROXIES) do
    if p.value ~= "direct" then
      gh_speed[p.value] = { testing = true }
      local t0 = host.now_ms()
      host.http({
        url = p.value .. GH_TEST_PATH, method = "GET", timeout = 10,
        on_done = function(res)
          if res and res.ok then
            gh_speed[p.value] = { ms = host.now_ms() - t0 }
          else
            gh_speed[p.value] = { err = "HTTP " .. tostring(res and res.status or "?") }
          end
          rev.set(rev.get() + 1)
        end,
        on_error = function() gh_speed[p.value] = { err = "失败" }; rev.set(rev.get() + 1) end,
      })
    end
  end
  rev.set(rev.get() + 1)
end
-- 直连置顶, 其余按延迟升序 (未测/失败沉底)
local function gh_sorted()
  local list = {}
  for _, p in ipairs(GH_PROXIES) do list[#list + 1] = p end
  table.sort(list, function(a, b)
    if a.value == "direct" then return true end
    if b.value == "direct" then return false end
    local sa, sb = gh_speed[a.value], gh_speed[b.value]
    local ma = (sa and sa.ms) or math.huge
    local mb = (sb and sb.ms) or math.huge
    if ma ~= mb then return ma < mb end
    return a.label < b.label
  end)
  return list
end
local function gh_status_widget(p)
  if p.value == "direct" then return text("默认", { size = 12, color = "grey" }) end
  local s = gh_speed[p.value]
  if not s or s.testing then
    return row({ spinner({ size = 14 }), spacer(6), text("测速中", { size = 12, color = "grey" }) }, { cross = "center" })
  elseif s.ms then
    local col = s.ms < 800 and "green" or (s.ms < 2000 and "orange" or "grey")
    return text(s.ms .. " ms", { size = 12, color = col, weight = "bold" })
  else
    return text(s.err or "失败", { size = 12, color = "red" })
  end
end
local function open_gh_dialog()
  gh_test_all()
  host.dialog({
    title = "GitHub 代理测速",
    build = function()
      local rows = {
        row({
          expanded(text("点选一个镜像作为下载代理", { size = 12, color = "grey" })),
          button("重新测速", gh_test_all, { variant = "text", icon = "refresh" }),
        }, { cross = "center" }),
        divider(),
      }
      for _, p in ipairs(gh_sorted()) do
        local sel = gh_proxy() == p.value
        rows[#rows + 1] = tile(p.label, {
          icon = sel and "radio_button_checked" or "radio_button_unchecked",
          trailing = gh_status_widget(p),
          onTap = function()
            host.set("environment_github_proxy", p.value)
            host.close_dialog()
            host.toast("已选择: " .. p.label)
          end,
        })
      end
      return box({ height = 400, child = scroll({ column(rows) }) })
    end,
    actions = { { label = "关闭", variant = "text" } },
  })
end

-- 选中代理时给下载 URL 加前缀 (direct 则直接 github.com)
local function gh_prefix(url)
  local p = gh_proxy()
  if p == "direct" or p == "auto" then return url end
  return p .. "/" .. url
end

local function env_pre()
  return table.concat({
    'export TMPDIR="' .. host.tmp_path() .. '"',
    'export SANDBOX_GITHUB_PROXY="' .. gh_proxy() .. '"',
    'export L_NOT_INSTALLED=未安装',
    'export L_INSTALLING=安装中',
    'export L_INSTALLED=已安装',
    'export UV_LINK_MODE=copy',
    'export UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"',
    'export UV_PYTHON_INSTALL_MIRROR="' ..
      gh_prefix("https://github.com/astral-sh/python-build-standalone/releases/download") .. '"',
  }, "\n")
end

local SH_HELPERS = [==[
progress_echo(){ echo -e "\033[31m- $@\033[0m"; echo "$@" > "$TMPDIR/progress_des"; }
repair_apt_dpkg(){
  export DEBIAN_FRONTEND=noninteractive
  echo "检查并修复 dpkg 状态 ..."
  if dpkg --configure -a; then
    echo "dpkg 状态正常"
    return 0
  fi
  echo "dpkg 修复未一次成功, 尝试清理陈旧锁后重试 ..."
  rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock 2>/dev/null || true
  dpkg --configure -a || return 1
}
]==]

local SH_NET = [==[
network_test() {
  target_proxy=""
  case "$SANDBOX_GITHUB_PROXY" in
    ""|direct|auto) echo "Github 直连"; return 0 ;;
    *) target_proxy="$SANDBOX_GITHUB_PROXY"; echo "使用代理: $target_proxy"; return 0 ;;
  esac
}
]==]

local SH_BASE = [==[
install_sudo_curl_git(){
  missing=()
  for cmd in sudo git curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then missing+=("$cmd"); fi
  done
  if [ ${#missing[@]} -eq 0 ]; then progress_echo "基础命令已安装"; return 0; fi
  progress_echo "基础命令缺失: ${missing[*]}, 开始安装..."
  export DEBIAN_FRONTEND=noninteractive
  repair_apt_dpkg || { echo "dpkg 修复失败, 请先在下方点「修复 apt/dpkg」"; return 1; }
  apt_opts="-o Acquire::ForceIPv4=true"
  apt-get $apt_opts update || echo "apt-get update 失败, 继续尝试..."
  if ! apt-get $apt_opts install -y sudo git curl; then echo "基础命令安装失败"; return 1; fi
  progress_echo "基础命令安装完成"
}
]==]

local SH_UV = [==[
install_uv(){
  INSTALL_DIR="$HOME/.local/bin"
  ARCHIVE_FILE="uv-aarch64-unknown-linux-gnu.tar.gz"
  mkdir -p "$INSTALL_DIR"
  network_test

  # 探测最新版本: 走 releases/latest 的 302 重定向, 取最终 URL 末段 tag (无需 api.github.com)
  progress_echo "检测 uv 最新版本..."
  LATEST_URL=$(curl -fsSL -o /dev/null -w '%{url_effective}' "${target_proxy:+${target_proxy}/}https://github.com/astral-sh/uv/releases/latest" 2>/dev/null)
  APP_VERSION="${LATEST_URL##*/}"
  case "$APP_VERSION" in
    ""|*latest*) APP_VERSION="0.9.9"; echo "无法获取最新版本, 回退到 $APP_VERSION" ;;
    *) echo "最新 uv 版本: $APP_VERSION" ;;
  esac

  # 未强制重装, 且已安装同版本 -> 跳过
  if [ "${UV_REINSTALL:-}" != "1" ] && [ -x "$INSTALL_DIR/uv" ]; then
    CUR=$("$INSTALL_DIR/uv" --version 2>/dev/null | awk '{print $2}')
    if [ -n "$CUR" ] && [ "$CUR" = "$APP_VERSION" ]; then
      progress_echo "uv 已是最新 ($CUR)"
      return 0
    fi
    echo "当前 uv ${CUR:-未知}, 将更新到 $APP_VERSION..."
  fi
  [ "${UV_REINSTALL:-}" = "1" ] && { echo "强制重装 uv..."; rm -f "$INSTALL_DIR/uv" "$INSTALL_DIR/uvx"; }

  progress_echo "uv $L_INSTALLING ($APP_VERSION)..."
  DOWNLOAD_URL="${target_proxy:+${target_proxy}/}https://github.com/astral-sh/uv/releases/download/${APP_VERSION}/${ARCHIVE_FILE}"
  TMP_DIR=$(mktemp -d)
  echo "正在下载 uv $APP_VERSION..."
  if ! curl -fL "$DOWNLOAD_URL" -o "$TMP_DIR/$ARCHIVE_FILE"; then echo "下载失败"; rm -rf "$TMP_DIR"; exit 1; fi
  if ! tar -C "$TMP_DIR" -xf "$TMP_DIR/$ARCHIVE_FILE" --strip-components 1; then echo "解压失败"; rm -rf "$TMP_DIR"; exit 1; fi
  cp "$TMP_DIR/uv" "$TMP_DIR/uvx" "$INSTALL_DIR/" && chmod +x "$INSTALL_DIR/uv" "$INSTALL_DIR/uvx"
  grep -q "$INSTALL_DIR" "$HOME/.bashrc" 2>/dev/null || echo "export PATH=$INSTALL_DIR:\$PATH" >> "$HOME/.bashrc"
  rm -rf "$TMP_DIR"
  progress_echo "uv 安装完成 ($APP_VERSION)"
}
]==]

local function env_installed(step)
  local ub = host.ubuntu_path()
  if step == "base" then
    return host.exists(ub .. "/usr/bin/git") and host.exists(ub .. "/usr/bin/curl") and host.exists(ub .. "/usr/bin/sudo")
  elseif step == "uv" then
    return host.exists(ub .. "/root/.local/bin/uv")
  end
  return false
end

local function install_base(_)
  host.spawn(env_pre() .. "\n" .. SH_HELPERS .. SH_BASE .. "\ninstall_sudo_curl_git\n", "基础命令")
end
local function repair_dpkg(_)
  host.spawn(env_pre() .. "\n" .. SH_HELPERS .. "\nrepair_apt_dpkg\n", "修复 apt/dpkg")
end
local function install_uv(reinstall)
  local pre = env_pre()
  if reinstall then pre = pre .. "\nexport UV_REINSTALL=1" end
  host.spawn(pre .. "\n" .. SH_HELPERS .. SH_NET .. SH_BASE .. SH_UV .. "\ninstall_sudo_curl_git\ninstall_uv\n", "uv")
end

local ENV_STEPS = {
  { id = "base", title = "基础命令", sub = "sudo / git / curl", icon = "build_circle_outlined", run = install_base },
  { id = "uv",   title = "uv",       sub = "Python 依赖管理工具", icon = "data_object", run = install_uv },
}

-- ============================================================
-- 小工具
-- ============================================================
local function chip_status(ok)
  return chip(ok and "已安装" or "未安装", { color = ok and "green" or "grey" })
end

-- 机器人页通用: 画廊风格的标题卡片
local function bot_hero(iconName, title, subtitle, desc, color)
  return card({
    row({
      box({ width = 56, height = 56, child = center(icon(iconName, { size = 28, color = "white" })),
        style = { bg = color or "primary", radius = 16, shadow = { color = "#33000000", blur = 8, dy = 3 } } }),
      spacer(12),
      expanded(column({
        text(title, { size = 20, weight = "bold" }),
        text(subtitle, { size = 12, color = "grey" }),
        spacer(4),
        text(desc, { size = 13, color = "grey" }),
      }, { gap = 2 })),
    }, { cross = "center" }),
  })
end

local function env_step_card(step)
  local ok = env_installed(step.id)
  local accent = ok and "green" or "primary"
  return card({
    row({
      box({ width = 44, height = 44, child = center(icon(step.icon or "extension", { size = 22, color = "white" })),
        style = { bg = accent, radius = 12, shadow = { color = "#22000000", blur = 6, dy = 2 } } }),
      spacer(12),
      expanded(column({
        text(step.title, { weight = "bold", size = 15 }),
        text(step.sub, { size = 12, color = "grey" }),
      }, { gap = 2 })),
      chip_status(ok),
    }, { cross = "center" }),
    spacer(10),
    button(ok and "重新安装" or "安装", function() step.run(ok) end,
      { variant = ok and "outlined" or "filled", icon = ok and "refresh" or "download" }),
  })
end

-- ============================================================
-- 主页 home
-- ============================================================
app.page("home", function(ctx)
  local dev = host.device_info() or {}
  return {
    card({
      column({
        text("MK-BOT", { size = 30, weight = "bold", color = "primary" }),
        spacer(4),
        text("Android QQ 机器人一体化运行平台", { size = 14, color = "grey" }),
        spacer(2),
        text("v" .. tostring(dev.appVersion or "0.0.1"), { size = 12, color = "grey" }),
        spacer(14),
        divider(),
        spacer(14),
        richtext({
          { text = "在手机上完成 ", size = 14 },
          { text = "NapCat", weight = "bold", color = "deepPurple" },
          { text = " 登录与托管, ", size = 14 },
          { text = "咔咔珂", weight = "bold", color = "pink" },
          { text = " 对接与扩展, ", size = 14 },
          { text = "Web 面板", weight = "bold", color = "teal" },
          { text = " 与 ", size = 14 },
          { text = "终端", weight = "bold", color = "indigo" },
          { text = " 一站管理。", size = 14 },
        }),
        spacer(12),
        wrap({
          chip("NapCat", { color = "deepPurple" }),
          chip("咔咔珂", { color = "pink" }),
          chip("Web 面板", { color = "teal" }),
          chip("Ubuntu 沙盒", { color = "primary" }),
        }, { spacing = 8, runSpacing = 8 }),
      }),
    }),

    section("Ubuntu 容器", {
      card({
        text("首次使用需解压 Ubuntu 系统到本地 (约 1–3 分钟)。应用启动时会自动安装; 也可手动触发。",
          { size = 13, color = "grey" }),
        spacer(10),
        button("安装 / 修复 Ubuntu 容器", function()
          host.install_rootfs(function()
            host.toast("Ubuntu 容器就绪")
          end)
        end, { variant = "filled", icon = "download" }),
      }),
    }),

    section("环境配置", {
      card("网络与系统", {
        tile("GitHub 代理", {
          subtitle = "当前: " .. gh_proxy_label(gh_proxy()) .. " · 点击测速并选择镜像",
          icon = "swap_horiz",
          onTap = open_gh_dialog,
        }),
        spacer(10),
        button("修复 apt / dpkg", function() repair_dpkg() end,
          { variant = "outlined", icon = "build_circle_outlined" }),
        text("若 git / NapCat 安装报 dpkg was interrupted, 请先修复再重试。", { size = 12, color = "grey" }),
      }),
      spacer(10),
      card("依赖工具", {
        column((function()
          local rows = {}
          for i, s in ipairs(ENV_STEPS) do
            rows[#rows + 1] = env_step_card(s)
            if i < #ENV_STEPS then rows[#rows + 1] = spacer(10) end
          end
          return rows
        end)(), { gap = 0 }),
      }),
    }),
  }
end)

-- ============================================================
-- NapCat 管理 (写法同 network / files; 构建期不访问 Ubuntu 文件系统)
-- ============================================================
app.page("napcat", function(ctx)
  local rev = state("napcat.rev", 0)
  rev.get()

  local inst_st = state("napcat.inst", "未检测")
  local dir_st = state("napcat.dir", "")
  local run_st  = state("napcat.run", "未检测")
  local port_st = state("napcat.port", tostring(host.get("napcat_webui_port") or "6099"))
  local url_st  = state("napcat.url", "http://127.0.0.1:" .. port_st.get())
  local proxy_rev = state("napcat.proxy.rev", 0)
  proxy_rev.get()

  local function get_nc()
    local ok, m = pcall(require, "napcat")
    return ok and m or nil
  end

  local function proxy_label()
    local nc = get_nc()
    return nc and nc.download_proxy_label() or "直连 nclatest (官方, 推荐)"
  end

  local function open_napcat_mirror_dialog()
    local nc = get_nc()
    if not nc then host.toast("napcat 模块未加载"); return end
    local cur = nc.download_proxy()
    host.dialog({
      title = "NapCat 安装包下载镜像",
      build = function()
        local rows = {
          card({
            text("独立于主页 GitHub 代理, 仅用于 NapCat install.sh 下载。", { size = 12, color = "grey" }),
            text("GitHub 镜像仅作用于 GitHub Raw 地址, 不会错误代理 nclatest 域名。", { size = 12, color = "grey" }),
          }),
        }
        for _, s in ipairs(nc.MIRROR_SOURCES) do
          local sel = cur == s.value
          rows[#rows + 1] = tile(s.label, {
            icon = sel and "radio_button_checked" or "radio_button_unchecked",
            onTap = function()
              host.set("napcat_download_proxy", s.value)
              proxy_rev.set(proxy_rev.get() + 1)
              host.close_dialog()
              host.toast("已选择: " .. s.label)
            end,
          })
        end
        return box({ height = 360, child = scroll({ column(rows) }) })
      end,
      actions = { { label = "关闭", variant = "text" } },
    })
  end

  local function sync_running()
    local r = ctx and ctx.running
    if r and (r["napcat"] == true or r.napcat == true) then
      run_st.set("运行中")
    else
      run_st.set("已停止")
    end
  end

  local function refresh()
    sync_running()
    local nc = get_nc()
    if not nc then
      inst_st.set("模块未加载")
      return
    end
    local ok, v = pcall(function() return nc.installed(true) end)
    inst_st.set((ok and v) and "已安装" or "未安装")
    if ok and v then
      local ok2, d = pcall(function() return nc.install_dir() end)
      dir_st.set((ok2 and d) and d or "")
    else
      dir_st.set("")
    end
    port_st.set(tostring(nc.webui_port()))
    url_st.set(nc.webui_url())
    rev.set(rev.get() + 1)
    host.toast("已刷新")
  end

  sync_running()

  local tab = state("napcat.tab", 1)

  local overview = column({
    bot_hero("pets_outlined", "NapCat", "Ubuntu 容器 · QQ 机器人 (OneBot V11)",
      "官方 Shell 安装, 管理启停并打开 WebUI 扫码登录。", "deepPurple"),
    card("运行状态", {
      wrap({
        chip(inst_st.get(), { color = inst_st.get() == "已安装" and "green" or "orange" }),
        chip(run_st.get(), { color = run_st.get() == "运行中" and "teal" or "grey" }),
      }, { spacing = 8, runSpacing = 8 }),
      spacer(12),
      tile("安装目录", { subtitle = dir_st.get() ~= "" and dir_st.get() or "未检测", icon = "folder" }),
      tile("WebUI", { subtitle = url_st.get(), icon = "language" }),
      spacer(8),
      wrap({
        button("刷新状态", refresh, { variant = "tonal", icon = "refresh" }),
        button("重新检测", function()
          local nc = get_nc()
          if nc then nc.rescan_install() else host.toast("模块未加载") end
        end, { variant = "tonal", icon = "search" }),
      }, { spacing = 8, runSpacing = 8 }),
    }),
  }, { gap = 12 })

  local control = column({
    card("框架控制", {
      wrap({
        button("安装 NapCat", function()
          local nc = get_nc()
          if not nc then host.toast("napcat 模块未加载"); return end
          nc.prompt_install(false)
        end, { variant = "filled", icon = "download" }),
        button("启动", function()
          local nc = get_nc()
          if not nc then host.toast("napcat 模块未加载"); return end
          nc.start(true)
        end, { variant = "tonal", icon = "play_arrow" }),
        button("停止", function()
          local nc = get_nc()
          if not nc then host.toast("napcat 模块未加载"); return end
          nc.stop()
        end, { variant = "outlined", icon = "stop" }),
        button("重启", function()
          local nc = get_nc()
          if not nc then host.toast("napcat 模块未加载"); return end
          nc.restart()
        end, { variant = "tonal", icon = "restart_alt" }),
      }, { spacing = 8, runSpacing = 8 }),
      spacer(8),
      text("安装 / 运行日志在任务弹窗中点「日志」查看; 后台运行不会跳转终端。", { size = 12, color = "grey" }),
    }),
    card("快捷操作", {
      wrap({
        button("打开 WebUI", function()
          local nc = get_nc()
          if nc then nc.open_webui(true) else host.toast("模块未加载") end
        end, { variant = "tonal", icon = "open_in_browser" }),
        button("修复 apt/dpkg", function()
          local nc = get_nc()
          if nc then nc.repair_dpkg() else host.toast("模块未加载") end
        end, { variant = "outlined", icon = "build_circle_outlined" }),
      }, { spacing = 8, runSpacing = 8 }),
    }),
  }, { gap = 12 })

  local config = column({
    card("WebUI 端口", {
      textfield({
        label = "WebUI 端口",
        hint = "6099",
        value = port_st.get(),
        onChanged = function(v)
          port_st.set(v)
          local n = tonumber(v)
          if n and n >= 1024 and n <= 65535 then
            host.set("napcat_webui_port", tostring(n))
            url_st.set("http://127.0.0.1:" .. n)
          end
        end,
      }),
      spacer(8),
      text("修改端口后需重启 NapCat。", { size = 12, color = "grey" }),
    }),
    card("下载与说明", {
      tile("安装包下载镜像", {
        subtitle = proxy_label(),
        icon = "swap_horiz",
        onTap = open_napcat_mirror_dialog,
      }),
      spacer(8),
      expansion("使用说明", {
        text("· 官方 Linux Shell 安装 (Rootless, 目录 ~/Napcat)", { size = 13 }),
        text("· 默认 WebUI 端口 6099", { size = 13 }),
        text("· 非官方协议, 存在封号风险", { size = 13, color = "orange" }),
      }, { icon = "info_outline" }),
    }),
  }, { gap = 12 })

  return tabs({
    active = tab.get(),
    onSelect = function(i) tab.set(i) end,
    align = "distribute",
    items = {
      { title = "概览", icon = "dashboard",       content = overview },
      { title = "控制", icon = "play_circle",     content = control },
      { title = "配置", icon = "tune",            content = config },
    },
  })
end)

-- ============================================================
-- Kakake 咔咔珂管理 (对齐 mk 脚本 menu_kakake 全功能)
-- ============================================================
app.page("kakake", function(ctx)
  local rev = state("kakake.rev", 0)
  rev.get()

  local inst_st = state("kakake.inst", "未检测")
  local node_st = state("kakake.node", "未检测")
  local run_st  = state("kakake.run", "未检测")
  local url_st  = state("kakake.url", "http://127.0.0.1:8787")
  local conn_st = state("kakake.conn", "0 条连接")
  local node_cfg_st = state("kakake.node_cfg", "22.23.0 · npmmirror")

  local function get_kk()
    local ok, m = pcall(require, "kakake")
    return ok and m or nil
  end

  local function sync_running()
    local kk = get_kk()
    if not kk then return end
    if kk.is_running(ctx) then
      run_st.set("运行中")
    else
      run_st.set("已停止")
    end
  end

  local function refresh()
    sync_running()
    local kk = get_kk()
    if not kk then
      inst_st.set("模块未加载")
      return
    end
    inst_st.set(kk.installed(true) and "已安装" or "未安装")
    node_st.set(kk.node_installed(true) and kk.node_version_text() or "未安装")
    url_st.set(kk.admin_url())
    node_cfg_st.set(kk.node_version() .. " · " .. kk.node_mirror_label())
    local n = #(kk.cfg_list())
    conn_st.set(n .. " 条连接")
    rev.set(rev.get() + 1)
    host.toast("已刷新")
  end

  sync_running()
  do
    local kk = get_kk()
    if kk then node_cfg_st.set(kk.node_version() .. " · " .. kk.node_mirror_label()) end
  end

  local tab = state("kakake.tab", 1)

  local overview = column({
    bot_hero("smart_toy_outlined", "咔咔珂", "Ubuntu 容器 · QQ/OneBot 机器人框架",
      "安装咔咔珂与 Node.js, 配置 OneBot 连接对接 NapCat。", "pink"),
    card("运行状态", {
      wrap({
        chip(inst_st.get(), { color = inst_st.get() == "已安装" and "green" or "orange" }),
        chip(node_st.get(), { color = node_st.get():sub(1, 2) == "未" and "orange" or "teal" }),
        chip(run_st.get(), { color = run_st.get() == "运行中" and "teal" or "grey" }),
      }, { spacing = 8, runSpacing = 8 }),
      spacer(12),
      tile("管理面板", { subtitle = url_st.get(), icon = "language" }),
      tile("连接配置", { subtitle = conn_st.get(), icon = "hub" }),
      spacer(8),
      button("刷新状态", refresh, { variant = "tonal", icon = "refresh" }),
    }),
  }, { gap = 12 })

  local control = column({
    card("咔咔珂", {
      wrap({
        button("安装咔咔珂", function()
          local kk = get_kk()
          if kk then kk.install(false) else host.toast("模块未加载") end
        end, { variant = "filled", icon = "download" }),
        button("启动", function()
          local kk = get_kk()
          if kk then kk.start() else host.toast("模块未加载") end
        end, { variant = "tonal", icon = "play_arrow" }),
        button("停止", function()
          local kk = get_kk()
          if kk then kk.stop() else host.toast("模块未加载") end
        end, { variant = "outlined", icon = "stop" }),
        button("重启", function()
          local kk = get_kk()
          if kk then kk.restart() else host.toast("模块未加载") end
        end, { variant = "tonal", icon = "restart_alt" }),
        button("卸载", function()
          local kk = get_kk()
          if kk then kk.uninstall() else host.toast("模块未加载") end
        end, { variant = "outlined", icon = "delete_forever" }),
      }, { spacing = 8, runSpacing = 8 }),
    }),
    card("Node.js", {
      wrap({
        button("安装 Node.js", function()
          local kk = get_kk()
          if kk then kk.install_node() else host.toast("模块未加载") end
        end, { variant = "filled", icon = "data_object" }),
        button("卸载 Node.js", function()
          local kk = get_kk()
          if kk then kk.uninstall_node() else host.toast("模块未加载") end
        end, { variant = "outlined", icon = "delete" }),
      }, { spacing = 8, runSpacing = 8 }),
      spacer(8),
      tile("Node 版本", {
        subtitle = node_cfg_st.get(),
        icon = "settings",
        onTap = function()
          local kk = get_kk()
          if not kk then host.toast("模块未加载"); return end
          host.dialog({
            title = "Node.js 设置",
            build = function()
              return card({
                tile("选择版本", {
                  subtitle = kk.node_version(),
                  icon = "tag",
                  onTap = function() host.close_dialog(); kk.open_node_version_dialog() end,
                }),
                tile("下载镜像", {
                  subtitle = kk.node_mirror_label(),
                  icon = "swap_horiz",
                  onTap = function() host.close_dialog(); kk.open_node_mirror_dialog() end,
                }),
              })
            end,
            actions = { { label = "关闭", variant = "text" } },
          })
        end,
      }),
      spacer(8),
      text("推荐顺序: 安装咔咔珂 → 安装 Node.js (arm64) → 配置连接 → 启动", { size = 12, color = "grey" }),
    }),
  }, { gap = 12 })

  local connect = column({
    card("连接与对接", {
      wrap({
        button("管理连接", function()
          local kk = get_kk()
          if kk then kk.open_conn_list_dialog(refresh) else host.toast("模块未加载") end
        end, { variant = "tonal", icon = "cable" }),
        button("打开管理面板", function()
          local kk = get_kk()
          if kk then kk.open_admin() else host.toast("模块未加载") end
        end, { variant = "tonal", icon = "open_in_browser" }),
        button("NapCat 对接说明", function()
          local kk = get_kk()
          if kk then kk.show_pairing_hint() else host.toast("模块未加载") end
        end, { variant = "outlined", icon = "help_outline" }),
      }, { spacing = 8, runSpacing = 8 }),
    }),
    card("说明", {
      expansion("使用说明", {
        text("· 咔咔珂安装包来自 mk 官方源 (kakake.zip)", { size = 13 }),
        text("· Node.js 需 ≥20, 默认 arm64 架构", { size = 13 }),
        text("· 管理面板默认端口 8787", { size = 13 }),
        text("· 对接 NapCat 常用: 反向 ws://127.0.0.1:6700", { size = 13 }),
        text("· 修改连接后需重启咔咔珂", { size = 13, color = "orange" }),
      }, { icon = "info_outline" }),
    }),
  }, { gap = 12 })

  return tabs({
    active = tab.get(),
    onSelect = function(i) tab.set(i) end,
    align = "distribute",
    items = {
      { title = "概览", icon = "dashboard",   content = overview },
      { title = "控制", icon = "play_circle", content = control },
      { title = "对接", icon = "hub",         content = connect },
    },
  })
end)

