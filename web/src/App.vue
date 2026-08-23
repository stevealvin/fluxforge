<template>
  <n-config-provider
    :theme="themeStore.isDark ? darkTheme : null"
    :theme-overrides="currentThemeOverrides"
    :locale="zhCN"
    :date-locale="dateZhCN"
  >
    <n-global-style />
    <n-loading-bar-provider>
      <n-message-provider>
        <n-notification-provider>
          <n-dialog-provider>
            <div
              class="min-h-screen h-screen flex flex-col transition-colors duration-300 font-sans overflow-hidden relative"
              :class="themeStore.isDark ? 'bg-[#08100d] text-zinc-100' : 'bg-[#f6f9f8] text-zinc-800'"
            >
              <!-- 🌟 FluxView 幻夜极光·翠影幽绿柔和微光晕 (使用全局 primary 变量与微光光斑) -->
              <div class="absolute -top-36 -left-36 w-[440px] h-[440px] bg-primary/10 dark:bg-primary/15 rounded-full blur-[140px] pointer-events-none z-0"></div>
              <div class="absolute top-1/3 -right-36 w-[440px] h-[440px] bg-teal-500/8 dark:bg-teal-500/12 rounded-full blur-[140px] pointer-events-none z-0"></div>
              <div class="absolute -bottom-36 left-1/3 w-[400px] h-[400px] bg-cyan-500/6 dark:bg-cyan-500/10 rounded-full blur-[140px] pointer-events-none z-0"></div>

              <div class="flex-1 flex flex-col min-w-0 h-full overflow-hidden relative z-10">
                <Layout />
              </div>
            </div>
          </n-dialog-provider>
        </n-notification-provider>
      </n-message-provider>
    </n-loading-bar-provider>
  </n-config-provider>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import {
  NConfigProvider,
  NGlobalStyle,
  NLoadingBarProvider,
  NMessageProvider,
  NNotificationProvider,
  NDialogProvider,
  darkTheme,
  zhCN,
  dateZhCN,
  type GlobalThemeOverrides,
  type ConfigProviderProps,
  createDiscreteApi
} from 'naive-ui';
import Layout from './views/layout/index.vue';
import { useThemeStore } from '@/stores/theme';

const themeStore = useThemeStore();

/**
 * 🌟 FluxView 全局主题色彩规范 (直接内置于 App.vue)
 * 供 Naive UI 组件库直接使用真实 Hex 色值进行底层 seemly 颜色混合运算
 */
const themeColors = {
  // 浅色模式 (纯净星暮翡翠)
  light: {
    primary: '#059669',        // Emerald-600 (主色)
    primaryHover: '#10b981',   // Emerald-500 (悬停色)
    primaryPressed: '#047857', // Emerald-700 (激活色)
    primarySuppl: '#34d399',   // Emerald-400 (副色)
    info: '#0d9488',           // Teal-600
    infoHover: '#0f766e',
    success: '#10b981',        // Emerald-500
    successHover: '#059669',
    warning: '#d97706',        // Amber-600
    warningHover: '#b45309',
    error: '#e11d48',          // Rose-600
    errorHover: '#be123c',
    bodyBg: '#f6f9f8',         // 浅色页面底色
    hoverColor: 'rgba(5, 150, 105, 0.05)',
  },
  // 深色模式 (曜夜极光墨晶)
  dark: {
    primary: '#10b981',        // Emerald-500 (主色)
    primaryHover: '#34d399',   // Emerald-400 (悬停色)
    primaryPressed: '#059669', // Emerald-600 (激活色)
    primarySuppl: '#6ee7b7',   // Emerald-300 (副色)
    info: '#2dd4bf',           // Teal-400
    infoHover: '#5eead4',
    success: '#34d399',        // Emerald-400
    successHover: '#6ee7b7',
    warning: '#fbbf24',        // Amber-400
    warningHover: '#fde68a',
    error: '#f87171',          // Red-400
    errorHover: '#fca5a5',
    bodyBg: '#08100d',         // 深色页面底色
    hoverColor: 'rgba(16, 185, 129, 0.08)',
  },
} as const;

// 统一连续 Squircle 大圆角系统规范
const commonBorderRadius = {
  borderRadius: '16px',
  borderRadiusSmall: '8px',
  borderRadiusMedium: '10px',
  borderRadiusLarge: '18px',
};

// 🌟 FluxView 浅色主题：基于内联 themeColors 单一源配置 Naive UI
const lightThemeOverrides: GlobalThemeOverrides = {
  common: {
    ...commonBorderRadius,
    fontFamily: "'Plus Jakarta Sans', 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Noto Sans SC', 'PingFang SC', sans-serif",
    // 品牌核心色系：使用 Hex 满足 Naive UI (seemly) 计算要求
    primaryColor: themeColors.light.primary,
    primaryColorHover: themeColors.light.primaryHover,
    primaryColorPressed: themeColors.light.primaryPressed,
    primaryColorSuppl: themeColors.light.primarySuppl,
    // 状态功能色系
    infoColor: themeColors.light.info,
    infoColorHover: themeColors.light.infoHover,
    successColor: themeColors.light.success,
    successColorHover: themeColors.light.successHover,
    warningColor: themeColors.light.warning,
    warningColorHover: themeColors.light.warningHover,
    errorColor: themeColors.light.error,
    errorColorHover: themeColors.light.errorHover,
    // 背景与文本
    bodyColor: themeColors.light.bodyBg,
    cardColor: '#ffffff',
    modalColor: '#ffffff',
    popoverColor: '#ffffff',
    tableColor: '#ffffff',
    textColorBase: '#18181b',
    textColor1: '#18181b',
    textColor2: '#3f3f46',
    textColor3: '#71717a',
    textColorDisabled: '#a1a1aa',
    // 全局边框与微拟态
    borderColor: 'rgba(0, 0, 0, 0.08)',
    dividerColor: 'rgba(0, 0, 0, 0.04)',
    hoverColor: themeColors.light.hoverColor,
  },
  Card: {
    borderRadius: '16px',
    color: '#ffffff',
    colorEmbedded: '#edf5f2',
    borderColor: 'transparent',
    boxShadow: 'var(--shadow-card)',
    actionColor: 'rgba(0, 0, 0, 0.015)',
    paddingSmall: '16px',
    paddingMedium: '20px',
    titleFontSizeMedium: '15px',
    titleFontWeight: '600',
  },
  Button: {
    borderRadiusTiny: '6px',
    borderRadiusSmall: '8px',
    borderRadiusMedium: '10px',
    borderRadiusLarge: '14px',
    fontWeight: '500',
  },
  Input: {
    borderRadius: '10px',
  },
  Select: {
    peers: {
      InternalSelectMenu: {
        borderRadius: '12px',
      },
      InternalSelection: {
        borderRadius: '10px',
      }
    }
  },
  Dropdown: {
    peers: {
      Popover: {
        borderRadius: '12px',
      }
    }
  },
  Tag: {
    borderRadius: '8px',
  },
  Tabs: {
    tabBorderRadius: '8px',
    colorSegment: '#edf5f2',
    tabTextColorSegment: '#71717a',
    tabTextColorHoverSegment: '#18181b',
    tabTextColorActiveSegment: themeColors.light.primary,
    tabColorSegment: '#ffffff',
    barColor: themeColors.light.primary,
    tabTextColorActiveLine: themeColors.light.primary,
    tabTextColorHoverLine: themeColors.light.primaryHover,
  },
  Dialog: {
    borderRadius: '18px',
  },
  Progress: {
    fillColor: themeColors.light.primary,
    fillColorSuccess: themeColors.light.primaryHover,
    fillColorWarning: themeColors.light.warning,
    fillColorError: themeColors.light.error,
  },
  List: {
    colorHover: themeColors.light.hoverColor,
    colorHoverModal: themeColors.light.hoverColor,
  },
  Tooltip: {
    peers: {
      Popover: {
        borderRadius: '8px',
      }
    }
  }
};

// 🌟 FluxView 深色主题：基于 themeColors 单一源配置 Naive UI
const darkThemeOverrides: GlobalThemeOverrides = {
  common: {
    ...commonBorderRadius,
    fontFamily: "'Plus Jakarta Sans', 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Noto Sans SC', 'PingFang SC', sans-serif",
    // 品牌核心色系：使用 Hex 满足 Naive UI (seemly) 计算要求
    primaryColor: themeColors.dark.primary,
    primaryColorHover: themeColors.dark.primaryHover,
    primaryColorPressed: themeColors.dark.primaryPressed,
    primaryColorSuppl: themeColors.dark.primarySuppl,
    // 状态功能色系
    infoColor: themeColors.dark.info,
    infoColorHover: themeColors.dark.infoHover,
    successColor: themeColors.dark.success,
    successColorHover: themeColors.dark.successHover,
    warningColor: themeColors.dark.warning,
    warningColorHover: themeColors.dark.warningHover,
    errorColor: themeColors.dark.error,
    errorColorHover: themeColors.dark.errorHover,
    // 背景与文本
    bodyColor: themeColors.dark.bodyBg,
    cardColor: 'rgba(12, 25, 21, 0.78)',
    modalColor: '#0e1f1a',
    popoverColor: '#0e1f1a',
    tableColor: 'rgba(12, 25, 21, 0.65)',
    textColorBase: '#fafafa',
    textColor1: '#f4f4f5',
    textColor2: '#e4e4e7',
    textColor3: '#a1a1aa',
    textColorDisabled: '#71717a',
    // 全局边框与微拟态
    borderColor: 'rgba(255, 255, 255, 0.12)',
    dividerColor: 'rgba(255, 255, 255, 0.05)',
    hoverColor: themeColors.dark.hoverColor,
  },
  Card: {
    borderRadius: '16px',
    color: 'rgba(13, 30, 25, 0.60)',
    colorEmbedded: 'rgba(16, 35, 29, 0.5)',
    borderColor: 'transparent',
    boxShadow: 'var(--shadow-card)',
    actionColor: 'rgba(255, 255, 255, 0.02)',
    paddingSmall: '16px',
    paddingMedium: '20px',
    titleFontSizeMedium: '15px',
    titleFontWeight: '600',
  },
  Button: {
    borderRadiusTiny: '6px',
    borderRadiusSmall: '8px',
    borderRadiusMedium: '10px',
    borderRadiusLarge: '14px',
    fontWeight: '500',
  },
  Input: {
    borderRadius: '10px',
  },
  Select: {
    peers: {
      InternalSelectMenu: {
        borderRadius: '12px',
      },
      InternalSelection: {
        borderRadius: '10px',
      }
    }
  },
  Dropdown: {
    peers: {
      Popover: {
        borderRadius: '12px',
      }
    }
  },
  Tag: {
    borderRadius: '8px',
  },
  Tabs: {
    tabBorderRadius: '8px',
    colorSegment: 'rgba(16, 35, 29, 0.6)',
    tabTextColorSegment: '#a1a1aa',
    tabTextColorHoverSegment: '#fafafa',
    tabTextColorActiveSegment: themeColors.dark.primary,
    tabColorSegment: 'rgba(16, 185, 129, 0.16)',
    barColor: themeColors.dark.primary,
    tabTextColorActiveLine: themeColors.dark.primary,
    tabTextColorHoverLine: themeColors.dark.primaryHover,
  },
  Dialog: {
    borderRadius: '18px',
  },
  Progress: {
    fillColor: themeColors.dark.primary,
    fillColorSuccess: themeColors.dark.primaryHover,
    fillColorWarning: themeColors.dark.warning,
    fillColorError: themeColors.dark.error,
  },
  List: {
    colorHover: themeColors.dark.hoverColor,
    colorHoverModal: themeColors.dark.hoverColor,
  },
  Tooltip: {
    peers: {
      Popover: {
        borderRadius: '8px',
      }
    }
  }
};

const currentThemeOverrides = computed(() => {
  return themeStore.isDark ? darkThemeOverrides : lightThemeOverrides;
});

const configProviderPropsRef = computed<ConfigProviderProps>(() => ({
  locale: zhCN,
  dateLocale: dateZhCN,
  theme: themeStore.isDark ? darkTheme : null,
  themeOverrides: currentThemeOverrides.value,
}));

const { message, notification, dialog, loadingBar } = createDiscreteApi(
  ['message', 'dialog', 'notification', 'loadingBar'],
  {
    configProviderProps: configProviderPropsRef
  }
);

window.$message = message;
window.$notification = notification;
window.$dialog = dialog;
window.$loadingBar = loadingBar;
</script>

<style scoped>
</style>
