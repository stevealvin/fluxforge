/// 网页视频手势增强引擎 (WebVideoGestureEngine)
/// 
/// 为 WebView 内置的 HTML5 视频播放提供原生级全功能手势交互：
/// 1. 严格限定范围：仅在播放视频窗口内滑动才触发，不影响网页其余区域的上下浏览与滚动；
/// 2. 水平横向滑动：快进/快退，屏幕中央高颜值毛玻璃 HUD 实时提示【+XXs】或【-XXs】与进度条；
/// 3. 左侧纵向滑动：调节视频画面亮度（0% ~ 100%），HUD 实时显示【亮度 XX%】与金色刻度；
/// 4. 右侧纵向滑动：调节视频播放音量（0% ~ 100%），HUD 实时显示【音量 XX%】与天蓝刻度；
/// 5. 长按视频区域：瞬时触发加速倍速播放 (倍率可在设置中配置)，松手恢复原速；
/// 6. 全局捕获级监听（Capture Phase）：穿透播放器遮罩层与弹幕层，同时绝不干扰网页原生全屏与控制按钮点击；
/// 7. 防全屏失焦与防死循环保护：屏蔽全屏切换引发的网页误判暂停与高频 pause 震荡死循环。
class WebVideoGestureEngine {
  WebVideoGestureEngine._();

  static final WebVideoGestureEngine instance = WebVideoGestureEngine._();

  /// 生成用于注入到 WebView 中的视频手势检测与 HUD 提示脚本
  ///
  /// [longPressSpeed] 长按瞬时加速倍率，由全局播放偏好注入，与原生 AuraPlayer 保持一致
  /// [longPressEnabled] 长按瞬时加速总开关，关闭后网页视频长按不再触发加速
  String buildVideoGestureScript({
    double longPressSpeed = 3.0,
    bool longPressEnabled = true,
  }) {
    return r'''
(function() {
  // 0. App 全局播放偏好注入：长按瞬时加速是否启用 (倍率见下方 __FF_LONG_PRESS_SPEED__)
  const FF_LONG_PRESS_ENABLED = __FF_LONG_PRESS_ENABLED__;

  // 1. 注入全屏防失焦与播放器防死循环保护
  try {
    Object.defineProperty(document, 'hidden', {
      get: () => false,
      configurable: true
    });
    Object.defineProperty(document, 'visibilityState', {
      get: () => 'visible',
      configurable: true
    });
  } catch (_) {}

  // 阻断全屏或活动播放时由页面失焦引发的恶意 visibilitychange
  window.addEventListener('visibilitychange', (e) => {
    const isFs = document.fullscreenElement || document.webkitFullscreenElement;
    const hasPlaying = Array.from(document.querySelectorAll('video')).some(v => !v.paused);
    if (isFs || hasPlaying) {
      e.stopImmediatePropagation();
    }
  }, true);

  // 阻断窗口 blur 引发的自动 pause
  window.addEventListener('blur', (e) => {
    const isFs = document.fullscreenElement || document.webkitFullscreenElement;
    if (isFs) {
      e.stopImmediatePropagation();
    }
  }, true);

  // 播放器高频震荡防抖：拦截在全屏模式或切换过程中同一视频短时间内反复调用的 pause 死循环
  try {
    const origPause = HTMLMediaElement.prototype.pause;
    const origPlay = HTMLMediaElement.prototype.play;

    HTMLMediaElement.prototype.pause = function() {
      const now = Date.now();
      this.__last_pause_call = now;
      const isFs = document.fullscreenElement || document.webkitFullscreenElement;
      if (isFs && this.__last_play_call && (now - this.__last_play_call < 120)) {
        return;
      }
      return origPause.apply(this, arguments);
    };

    HTMLMediaElement.prototype.play = function() {
      this.__last_play_call = Date.now();
      return origPlay.apply(this, arguments);
    };
  } catch (_) {}

  // 避免手势监听重复安装
  if (window.__fluxforge_video_gestures_installed) {
    return;
  }
  window.__fluxforge_video_gestures_installed = true;

  // 2. 注入专属高颜值毛玻璃 HUD 样式表 (紧凑版，尺寸经过压缩)
  const styleId = '__ff_video_hud_style';
  function ensureStyleMounted() {
    if (!document.getElementById(styleId)) {
      const style = document.createElement('style');
      style.id = styleId;
      style.textContent = `
        .__ff_video_hud {
          position: fixed;
          left: 50%;
          top: 50%;
          transform: translate(-50%, -50%) scale(0.9);
          background: rgba(15, 23, 42, 0.55);
          backdrop-filter: blur(28px);
          -webkit-backdrop-filter: blur(28px);
          border: 1px solid rgba(255, 255, 255, 0.24);
          border-radius: 14px;
          padding: 10px 18px;
          color: #ffffff;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          box-shadow: 0 12px 32px rgba(0, 0, 0, 0.60);
          z-index: 2147483647;
          pointer-events: none;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 3px;
          transition: opacity 0.18s ease, transform 0.18s ease;
          opacity: 0;
          user-select: none;
        }
        .__ff_video_hud.active {
          opacity: 1;
          transform: translate(-50%, -50%) scale(1);
        }
        .__ff_hud_delta {
          font-size: 17px;
          font-weight: 700;
          letter-spacing: 0.4px;
          display: flex;
          align-items: center;
          gap: 4px;
          line-height: 1.15;
          text-shadow: 0 1px 4px rgba(0, 0, 0, 0.55); /* 半透明底上保证彩色文字可读性 */
        }
        .__ff_hud_delta.forward {
          color: #10B981; /* 翡翠绿 快进 */
        }
        .__ff_hud_delta.rewind {
          color: #F59E0B; /* 琥珀金 快退 */
        }
        .__ff_hud_delta.brightness {
          color: #FBBF24; /* 晨曦金 亮度 */
        }
        .__ff_hud_delta.volume {
          color: #38BDF8; /* 曜夜蓝 音量 */
        }
        .__ff_hud_time {
          font-size: 11px;
          color: rgba(255, 255, 255, 0.82);
          font-weight: 500;
          letter-spacing: 0.2px;
          line-height: 1.2;
        }
        .__ff_hud_progress_track {
          width: 126px;
          height: 3px;
          background: rgba(255, 255, 255, 0.25);
          border-radius: 2px;
          overflow: hidden;
          margin-top: 2px;
        }
        .__ff_hud_progress_bar {
          height: 100%;
          background: #10B981;
          width: 0%;
          border-radius: 2px;
          transition: width 0.04s linear, background 0.15s ease;
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    }
  }

  // 3. 动态挂载 HUD 节点（全屏时自适应移入全屏根节点，保证在全屏模式下依然清晰可见）
  let hud = null;
  function ensureHudMounted() {
    ensureStyleMounted();
    const fs = document.fullscreenElement || document.webkitFullscreenElement;
    const targetParent = fs || document.body || document.documentElement;
    if (!hud) {
      hud = document.createElement('div');
      hud.id = '__ff_video_hud';
      hud.className = '__ff_video_hud';
      hud.innerHTML = `
        <div class="__ff_hud_delta" id="__ff_hud_delta">+0s</div>
        <div class="__ff_hud_time" id="__ff_hud_time">00:00 / 00:00</div>
        <div class="__ff_hud_progress_track" id="__ff_hud_progress_track">
          <div class="__ff_hud_progress_bar" id="__ff_hud_progress_bar"></div>
        </div>
      `;
    }
    if (hud.parentElement !== targetParent) {
      targetParent.appendChild(hud);
    }
    return hud;
  }

  // 监听全屏切换，自动迁移 HUD 节点
  const onFsChange = () => {
    if (hud) {
      ensureHudMounted();
    }
  };
  document.addEventListener('fullscreenchange', onFsChange);
  document.addEventListener('webkitfullscreenchange', onFsChange);

  function formatTime(seconds) {
    if (isNaN(seconds) || seconds < 0) seconds = 0;
    const m = Math.floor(seconds / 60);
    const s = Math.floor(seconds % 60);
    const mm = m < 10 ? '0' + m : m;
    const ss = s < 10 ? '0' + s : s;
    if (m >= 60) {
      const h = Math.floor(m / 60);
      const remM = m % 60;
      const hh = h < 10 ? '0' + h : h;
      const rmm = remM < 10 ? '0' + remM : remM;
      return hh + ':' + rmm + ':' + ss;
    }
    return mm + ':' + ss;
  }

  let hudHideTimer = null;

  // 底部进度刻度条的显隐控制：
  // 亮度/音量需要刻度条体现百分比；快进/快退仅保留「秒数 + 时间」两行信息，隐藏进度条
  function setProgressTrackVisible(visible) {
    const trackEl = document.getElementById('__ff_hud_progress_track');
    if (trackEl) trackEl.style.display = visible ? '' : 'none';
  }

  function showSeekHud(deltaSeconds, targetTime, totalDuration) {
    if (hudHideTimer) clearTimeout(hudHideTimer);
    ensureHudMounted();
    const deltaEl = document.getElementById('__ff_hud_delta');
    const timeEl = document.getElementById('__ff_hud_time');
    if (!deltaEl || !timeEl || !hud) return;

    setProgressTrackVisible(false);

    const isForward = deltaSeconds >= 0;
    const sign = isForward ? '+' : '';
    // 纯数值 + 配色区分方向（绿=快进 / 金=快退），不再使用 emoji 图标
    deltaEl.textContent = `${sign}${deltaSeconds}s`;
    deltaEl.className = '__ff_hud_delta ' + (isForward ? 'forward' : 'rewind');

    timeEl.textContent = `${formatTime(targetTime)} / ${formatTime(totalDuration)}`;

    hud.classList.add('active');
  }

  function showBrightnessHud(percent) {
    if (hudHideTimer) clearTimeout(hudHideTimer);
    ensureHudMounted();
    const deltaEl = document.getElementById('__ff_hud_delta');
    const timeEl = document.getElementById('__ff_hud_time');
    const barEl = document.getElementById('__ff_hud_progress_bar');
    if (!deltaEl || !timeEl || !barEl || !hud) return;

    setProgressTrackVisible(true);

    deltaEl.textContent = `亮度 ${percent}%`;
    deltaEl.className = '__ff_hud_delta brightness';
    barEl.style.background = '#FBBF24';

    timeEl.textContent = '左侧上下滑动调节画面亮度';
    barEl.style.width = percent + '%';

    hud.classList.add('active');
  }

  function showVolumeHud(percent) {
    if (hudHideTimer) clearTimeout(hudHideTimer);
    ensureHudMounted();
    const deltaEl = document.getElementById('__ff_hud_delta');
    const timeEl = document.getElementById('__ff_hud_time');
    const barEl = document.getElementById('__ff_hud_progress_bar');
    if (!deltaEl || !timeEl || !barEl || !hud) return;

    setProgressTrackVisible(true);

    deltaEl.textContent = `音量 ${percent}%`;
    deltaEl.className = '__ff_hud_delta volume';
    barEl.style.background = '#38BDF8';

    timeEl.textContent = '右侧上下滑动调节播放音量';
    barEl.style.width = percent + '%';

    hud.classList.add('active');
  }

  function showStatusHud(title, subtitle) {
    if (hudHideTimer) clearTimeout(hudHideTimer);
    ensureHudMounted();
    const deltaEl = document.getElementById('__ff_hud_delta');
    const timeEl = document.getElementById('__ff_hud_time');
    const barEl = document.getElementById('__ff_hud_progress_bar');
    if (!deltaEl || !timeEl || !barEl || !hud) return;

    setProgressTrackVisible(true);

    deltaEl.textContent = title;
    deltaEl.className = '__ff_hud_delta forward';
    timeEl.textContent = subtitle || '';
    barEl.style.width = '100%';
    barEl.style.background = '#10B981';

    hud.classList.add('active');
  }

  function hideHud() {
    if (hudHideTimer) clearTimeout(hudHideTimer);
    hudHideTimer = setTimeout(() => {
      if (hud) hud.classList.remove('active');
    }, 450);
  }

  // 4. 智能检测触点下方活跃的目标视频与包围盒 (解决遮罩层/弹幕层/复杂组件层遮挡问题)
  function findActiveVideoAndRectAtPoint(x, y) {
    // A. 处于全屏时，优先定位全屏容器内的视频
    const fs = document.fullscreenElement || document.webkitFullscreenElement;
    if (fs) {
      const fv = fs.tagName === 'VIDEO' ? fs : fs.querySelector('video');
      if (fv) {
        return { video: fv, rect: fs.getBoundingClientRect() };
      }
    }

    const allVideos = Array.from(document.querySelectorAll('video'));
    if (allVideos.length === 0) return null;

    // B. 优先匹配触点直接命中的 video 元素
    for (const v of allVideos) {
      const rect = v.getBoundingClientRect();
      if (rect.width > 30 && rect.height > 30) {
        if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) {
          return { video: v, rect: rect };
        }
      }
    }

    // C. 匹配父级播放器外层容器（解决 .touch-layer、.mask 兄弟或祖先覆盖层遮挡）
    for (const v of allVideos) {
      let p = v.parentElement;
      let depth = 0;
      while (p && p !== document.body && p !== document.documentElement && depth < 6) {
        const rect = p.getBoundingClientRect();
        if (rect.width > 50 && rect.height > 50 && 
            rect.width <= (window.innerWidth || 1000) * 1.05 && 
            rect.height <= (window.innerHeight || 1000) * 1.05) {
          if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) {
            return { video: v, rect: rect };
          }
        }
        p = p.parentElement;
        depth++;
      }
    }

    // D. 单活跃视频宽容匹配（页面仅有 1 个正在播放的视频时，允许在播放器区域及其边界内触发）
    const playing = allVideos.filter(v => !v.paused && v.currentTime > 0);
    if (playing.length === 1) {
      const v = playing[0];
      const rect = v.getBoundingClientRect();
      if (rect.width > 50 && rect.height > 50) {
        if (x >= rect.left - 15 && x <= rect.right + 15 && 
            y >= rect.top - 15 && y <= rect.bottom + 15) {
          return { video: v, rect: rect };
        }
      }
    }

    return null;
  }

  // 5. 全局捕获阶段（Capture Phase）手势核心分治调度
  let currentVideo = null;
  let activeTargetRect = null;
  let isTouching = false;
  let startX = 0;
  let startY = 0;
  let isLeftRegion = true;
  let initialTime = 0;
  let totalDuration = 0;
  let initialBrightness = 1.0;
  let initialVolume = 1.0;
  let seekDeltaSeconds = 0;
  let targetSeekTime = 0;
  let gestureType = null; // null | 'seek' | 'brightness' | 'volume'
  let isGesturing = false;
  let longPressTimer = null;
  let isFastForwarding = false;
  let normalPlaybackRate = 1.0;

  function onGlobalTouchStart(e) {
    if (e.touches.length !== 1) return;
    const touch = e.touches[0];

    const match = findActiveVideoAndRectAtPoint(touch.clientX, touch.clientY);
    if (!match) return;

    currentVideo = match.video;
    activeTargetRect = match.rect;

    isTouching = true;
    startX = touch.clientX;
    startY = touch.clientY;
    initialTime = currentVideo.currentTime || 0;
    totalDuration = currentVideo.duration || 0;
    gestureType = null;
    isGesturing = false;
    seekDeltaSeconds = 0;
    targetSeekTime = initialTime;

    const relativeX = touch.clientX - activeTargetRect.left;
    isLeftRegion = relativeX < (activeTargetRect.width * 0.5);

    const filterMatch = (currentVideo.style.filter || '').match(/brightness\(([\d.]+)\)/);
    initialBrightness = filterMatch ? parseFloat(filterMatch[1]) : 1.0;

    initialVolume = currentVideo.muted ? 0.0 : (currentVideo.volume !== undefined ? currentVideo.volume : 1.0);

    // 长按 450ms 触发瞬时加速 (开关与倍率均由 App 全局播放偏好注入)
    // 注意：开关判断必须放在定时器回调内，不能在函数里提前 return，
    // 否则会跳过上方 initialVolume / initialBrightness 等初始化，破坏左右滑动调节
    if (longPressTimer) clearTimeout(longPressTimer);
    longPressTimer = setTimeout(() => {
      if (FF_LONG_PRESS_ENABLED && isTouching && !isGesturing && currentVideo && !currentVideo.paused) {
        isFastForwarding = true;
        normalPlaybackRate = currentVideo.playbackRate || 1.0;
        currentVideo.playbackRate = __FF_LONG_PRESS_SPEED__;
        showStatusHud('__FF_LONG_PRESS_SPEED__X 瞬时倍速中', '松开手指恢复原速');
      }
    }, 450);
  }

  function onGlobalTouchMove(e) {
    if (!isTouching || !currentVideo || e.touches.length !== 1) return;
    const touch = e.touches[0];
    const deltaX = touch.clientX - startX;
    const deltaY = touch.clientY - startY;

    if (Math.hypot(deltaX, deltaY) > 10 && longPressTimer) {
      clearTimeout(longPressTimer);
      longPressTimer = null;
    }

    if (isFastForwarding) return;

    if (!gestureType) {
      const absX = Math.abs(deltaX);
      const absY = Math.abs(deltaY);
      if (absX > 12 && absX > absY * 1.15) {
        gestureType = 'seek';
        isGesturing = true;
      } else if (absY > 12 && absY > absX * 1.15) {
        gestureType = isLeftRegion ? 'brightness' : 'volume';
        isGesturing = true;
      }
    }

    if (isGesturing) {
      // 阻止网页整体上下滚动以及原生事件冲突
      if (e.cancelable) {
        e.preventDefault();
      }
      e.stopPropagation();

      const rect = activeTargetRect || currentVideo.getBoundingClientRect();
      const elementHeight = rect.height || window.innerHeight || 300;
      const elementWidth = rect.width || window.innerWidth || 360;

      if (gestureType === 'brightness') {
        const deltaRatioY = -deltaY / elementHeight;
        let b = Math.max(0.2, Math.min(1.2, initialBrightness + deltaRatioY * 1.3));
        currentVideo.style.filter = `brightness(${b.toFixed(2)})`;
        const percent = Math.round(((b - 0.2) / 1.0) * 100);
        showBrightnessHud(percent);
      } else if (gestureType === 'volume') {
        const deltaRatioY = -deltaY / elementHeight;
        let v = Math.max(0.0, Math.min(1.0, initialVolume + deltaRatioY * 1.3));
        currentVideo.volume = v;
        if (v > 0 && currentVideo.muted) {
          currentVideo.muted = false;
        }
        const percent = Math.round(v * 100);
        showVolumeHud(percent);
      } else if (gestureType === 'seek') {
        const ratio = deltaX / elementWidth;
        let maxSeekScale = 90;
        if (totalDuration > 0) {
          if (totalDuration <= 180) {
            maxSeekScale = Math.max(30, totalDuration * 0.4);
          } else if (totalDuration >= 1800) {
            maxSeekScale = 180;
          }
        }

        seekDeltaSeconds = Math.round(ratio * maxSeekScale);
        targetSeekTime = initialTime + seekDeltaSeconds;
        if (totalDuration > 0) {
          targetSeekTime = Math.max(0, Math.min(totalDuration, targetSeekTime));
        } else {
          targetSeekTime = Math.max(0, targetSeekTime);
        }

        showSeekHud(seekDeltaSeconds, targetSeekTime, totalDuration);
      }
    }
  }

  function onGlobalTouchEnd(e) {
    if (longPressTimer) {
      clearTimeout(longPressTimer);
      longPressTimer = null;
    }

    if (isFastForwarding && currentVideo) {
      currentVideo.playbackRate = normalPlaybackRate;
      isFastForwarding = false;
      hideHud();
    }

    if (isGesturing) {
      if (gestureType === 'seek' && currentVideo && seekDeltaSeconds !== 0) {
        currentVideo.currentTime = targetSeekTime;
      }
      hideHud();
      if (e.cancelable) e.preventDefault();
      e.stopPropagation();
    }

    // 重置触摸状态（注意：若非滑动操作，纯点击完全放行给网页原生控件，不拦截全屏或播放按钮）
    isTouching = false;
    isGesturing = false;
    gestureType = null;
    currentVideo = null;
    activeTargetRect = null;
    seekDeltaSeconds = 0;
  }

  // 注册顶层全局捕获级手势监听器 (capture: true)
  window.addEventListener('touchstart', onGlobalTouchStart, { capture: true, passive: false });
  window.addEventListener('touchmove', onGlobalTouchMove, { capture: true, passive: false });
  window.addEventListener('touchend', onGlobalTouchEnd, { capture: true, passive: false });
  window.addEventListener('touchcancel', onGlobalTouchEnd, { capture: true, passive: false });

})();
'''
        // 长按加速开关与倍率由全局播放偏好注入 (与原生 AuraPlayer 共用同一设置项)
        .replaceAll('__FF_LONG_PRESS_SPEED__', longPressSpeed.toStringAsFixed(1))
        .replaceAll('__FF_LONG_PRESS_ENABLED__', longPressEnabled ? 'true' : 'false');
  }
}
